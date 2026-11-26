import {snapshotClientRequest} from '@actql/client-wire';
import {requestPreparationAvailable,openRequestPreparation,checkedPreparation} from '../local-node/request-preparation-adapter.mjs';
import {freezeInput} from '../../packages/sdk/internal/private-source-preparation.mjs';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';
import {types} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import {checkedRequestProgramPreparation,
  requestProgramCapacityRefusal} from './client-program-preparation.mjs';
import {diagnosticObserver} from '../host-common/diagnostic-observer.mjs';
import {runtimeIsError, runtimeOptionalField} from '../host-common/compiler-binding.generated.mjs';
import {createOrdinarySourceReaders} from './ordinary-source-reader.mjs';
import {createOrdinarySourceProducerCustody} from './ordinary-source-producer-custody.mjs';
import {createOrdinarySourceRequestCustody} from './ordinary-source-request-custody.mjs';
import {createOrdinarySourceRunCustody} from './ordinary-source-run-custody.mjs';
import {constructRequestDomain, createOrdinarySourceModelMaterials} from './ordinary-source-model-materials.mjs';
import resourceRuntime from './ordinary-node-resource-runtime.cjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {localContractLimits} from './local-values-plan.mjs';
import {assertOriginalClientRequestJournal} from './client-request-journal.mjs';
import {retireNodeInferOriginalRead, finishNodeInferOriginalReadScopes} from './infer-operation.mjs';
import {inferOriginalReadStartupCapacity} from './infer-original-installation.mjs';
import {readInstalledModelExecution} from './installed-model.mjs';
import {sourceAliasDataGeometry} from './source-alias-construction.mjs';

import type {OrdinarySourceRun} from './ordinary-source-run-custody.mjs';
import type {SourceProducerCustody} from './ordinary-source-producer-custody.mjs';
import type {OrdinarySourceRequestState} from './ordinary-source-request-custody.mjs';
import type {OrdinaryModelMaterialsState} from './ordinary-source-model-materials.mjs';
import type {SourceReaderChild} from './ordinary-source-reader.mjs';
import type {installedEffectModelPreparation} from './installed-effect-managed-run.mjs';
import type {openClientRequestJournal} from './client-request-journal.mjs';

type InstalledEffectModelRun = Parameters<typeof installedEffectModelPreparation>[0];
type KeyedEffectPreparation = NonNullable<InstalledEffectModelRun['keyedPreparation']> & Readonly<{
  compiled: Parameters<PublicationControl['bindCheckedClientRequestEffectKeyedOriginal']>[4];
}>;
type SourceOccurrence = Readonly<{stage: number; input: number; task: number; computeTask?: number}>;
type PhysicalReader = NonNullable<SourceReaderChild['reader']>;
type ModelCoordinate = readonly [stage: number, input: number, task: number];
type RequestSnapshot = Readonly<{
  kind: string; input: unknown; parameters?: unknown; stopBefore?: unknown; readOnly?: unknown; executionProfile?: unknown;
}>;
type RequestJournal = ReturnType<typeof openClientRequestJournal>;
type StaticPlanLimits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number;
  acquiredPlanAuthorization?: Readonly<{connection: () => boolean; accountMetadata: () => unknown;
    retainEgress(assertCurrent: () => void): void}>}>;
type StaticExplanationWires = Readonly<{plan: string; facts: string; context: string}>;
type StaticExplanationVisitor<Value> = (wires: StaticExplanationWires, assertCurrent: () => void) => Value;
type VerifyOriginalPolicy = (subject: unknown, options: Readonly<{signal: AbortSignal | undefined}>) => unknown;
type StaticModelInstallation = Parameters<typeof readInstalledModelExecution>[2];
type ModelExecutionRuntime = Parameters<typeof readInstalledModelExecution>[0];
type EffectExplanationCapture = ReturnType<typeof runtimeCore>['publicationControl']['captureOriginalEffectRunPlan'];
type EffectPlanEvidence = Parameters<EffectExplanationCapture>[3];
type EffectExplanationFacts = Readonly<{
  prepared: object; allowed: unknown; definition: unknown; runDefinition: Parameters<EffectExplanationCapture>[1];
}>;
type FundedRequest = Readonly<{
  kind: string | undefined; prepared: object;
  originalInputs: Readonly<{environment: unknown; parameters: undefined; parametersCursor: unknown}>;
}>;
type PrepareComputation = (parent: unknown, receipt: object, input: unknown, parameters: unknown,
  environment: unknown, preparedEnvironment: unknown, maxRows: number | undefined) => unknown;
// Scalar positions follow the installed Common entry points. Checked results,
// Request holders and borrowed compiler objects remain opaque.
type RequestComputationRuntime = Readonly<{
  clientProgramAcquisitionCount(prepared: object): number;
  clientProgramPrepareRequestNativeComputation?: PrepareComputation;
  clientProgramPrepareRequestSourceComputation?: PrepareComputation;
  clientProgramFinishRequestComputation?(parent: unknown, receipt: object, environment: unknown, preparedEnvironment: unknown): unknown;
  clientProgramPrepareRequestPolicySubjects?(parent: unknown, receipt: object, environment: unknown): unknown;
  clientProgramReadRequestPolicySubject?(parent: unknown, receipt: object, environment: unknown, index: number): unknown;
  clientProgramBindRequestPolicySubject?(parent: unknown, receipt: object, environment: unknown, index: number,
    policyCid: string | undefined): unknown;
  clientProgramFinishRequestPolicySubjects?(parent: unknown, receipt: object, environment: unknown): unknown;
  clientProgramBorrowRequestContentPlanInput?(parent: unknown, receipt: object): unknown;
  clientProgramBorrowRequestModelPlanInput?(parent: unknown, receipt: object): unknown;
  clientProgramBorrowRequestProgramPlanInput(parent: unknown, receipt: object): unknown;
  clientProgramComposedInferOccurrences?(prepared: object): unknown;
  clientProgramSerializationOccurrences?(prepared: object): unknown;
  clientProgramRequiresQueryTime?(prepared: object, maxNodes: number, maxWork: number): unknown;
  clientProgramRequestParametersOriginal(parent: unknown, receipt: object): unknown;
  clientProgramPrepareRequestProgramModuleBody(parent: unknown, receipt: object, admission: unknown,
    retainedRelationOutput: boolean, invocation: unknown, maxWork: number | undefined): unknown;
}>;
type RequestEffectExplanationRuntime = Readonly<{
  clientProgramTryCaptureEffectRunExplanation?(parent: unknown, receipt: object, allowed: unknown,
    definition: unknown, maxBytes: number, maxNodes: number, maxDepth: number, maxWork: number): unknown;
  clientProgramEffectRunExplanationWires?(scope: unknown, definition: unknown): unknown;
  clientProgramDiscardEffectRunExplanation?(scope: unknown, definition: unknown, abandoned: boolean): unknown;
}>;
type RequestModelGraphRuntime = Readonly<{
  clientProgramPrepareRequestProviderModelGraph?(parent: unknown, receipt: object, occurrence: unknown,
    execution: unknown, admission: unknown, provider: unknown, declarations: readonly unknown[] | undefined): unknown;
  clientProgramPrepareRequestModelGraph?(parent: unknown, receipt: object, occurrence: unknown,
    execution: unknown, admission: unknown): unknown;
  clientProgramPrepareRequestDeclaredFileModelGraph?(parent: unknown, receipt: object, occurrence: unknown,
    execution: unknown, admission: unknown, declarations: readonly unknown[]): unknown;
  clientProgramPrepareRequestSerializedModelGraph?(parent: unknown, receipt: object, occurrence: unknown,
    serializationGraph: unknown, execution: unknown, admission: unknown): unknown;
  clientProgramPrepareRequestModelsCompilation?(parent: unknown, receipt: object, graphs: readonly unknown[], admission: unknown): unknown;
  clientProgramPrepareRequestModelCompilation?(parent: unknown, receipt: object, graph: unknown, admission: unknown): unknown;
}>;
type ConstructContentGraph = (parent: unknown, receipt: object, admission: unknown, effectful?: true) => unknown;
type CompileContentGraph = (parent: unknown, receipt: object, graph: unknown, admission: unknown) => unknown;
type PlanConstructor = (parent: unknown, receipt: object) => unknown;
type InvocationConstructor = (artifact: unknown) => unknown;
type CapturePlanConstructor = (invocation?: unknown) => unknown;
type RetainedContentPreparation = NonNullable<OrdinarySourceRequestState['contentPreparation']> & {
  prepared: object; retired: boolean; inputHolder?: unknown;
};
type ModelPlanConstructor = (parent: unknown, receipt: object, compilation: unknown) => unknown;
type ModelQuantityLimits = NonNullable<NonNullable<InstalledEffectModelRun['modelSelection']>['quantityCapacity']>['limits'];
type PublicationControl = ReturnType<typeof runtimeCore>['publicationControl'];
type ModelRecovery = NonNullable<OrdinaryModelMaterialsState['recovery']>;
type RecoveryDefinition = ModelRecovery['definition'] & Readonly<{identity: string}>;
type RecoveryPlan = Readonly<{compiled: object; runDefinition: RecoveryDefinition}>;
type RecoverySelection = Readonly<{
  graph: object; restoredRun?: ModelRecovery['restored']; components?: readonly RecoverySelection[];
  quantityCapacity?: Readonly<{limits: ModelQuantityLimits}>;
}>;
type RecoveryCensus = Readonly<{maxReservations: number; maxHoldings: number; maxDelegations: number}>;
type RecoveryReadBudget = RecoveryCensus & Readonly<{
  modelRetainedBytes: bigint; modelExecutionBytes: bigint; readRetainedBytes: bigint; readExecutionBytes: bigint;
}>;
type RecoveryReadInstallation = Readonly<{nodeInstallation: unknown}>;
type RecoveryModel = {
  prepared: object; control: PublicationControl; compiled: object; runDefinition: RecoveryDefinition;
  graph: object; selection: RecoverySelection; budget?: RecoveryCensus; scope?: unknown;
  scopes?: unknown; components?: readonly RecoveryMember[]; closed?: boolean; scopeFinished?: boolean;
  taken?: boolean; hostAttempted?: boolean; publicationCapacity(): unknown;
};
type RecoveryMember = RecoveryModel & {
  budget: RecoveryReadBudget; selectedBounds?: unknown; originalReadInstallation?: RecoveryReadInstallation;
  read?: unknown; readAttempted?: boolean; readFailure?: unknown;
};
type RecoveryCapture = Readonly<{capture: Readonly<{source(): unknown}>}>;
type RecoveryReadFields = Readonly<{
  selection: RecoverySelection; control: PublicationControl; compiled: object; runDefinition: RecoveryDefinition;
  scope: unknown; publicationCapacity(): unknown; assertRuntimeCurrent(): void;
  readRetainedBytes: bigint; readExecutionBytes: bigint; modelRetainedBytes: bigint; modelExecutionBytes: bigint;
  nodeInstallation?: unknown; metadataInstallation?: RecoveryReadInstallation;
}>;
type RecoveryRead = RecoveryReadFields & Readonly<{
  retain(): void;
  prepareRead(): RecoveryReadFields & Readonly<{read: unknown}>;
  restoreRead(input: Readonly<{savedScope?: unknown}> | undefined): RecoveryReadFields & Readonly<{read: unknown}>;
  retire(): Promise<boolean>;
}>;
type RecoveryView = (RecoveryRead | Readonly<{
  selection: RecoverySelection; control: PublicationControl; compiled: object; runDefinition: RecoveryDefinition;
  components: readonly RecoveryRead[]; scopes: readonly unknown[];
  assertRuntimeCurrent(): void; retain(): void; retire(): Promise<boolean>;
}>) & Readonly<{
  prepareSource<Value extends object>(occurrence: SourceOccurrence, construct: (input: unknown) => Value): Value;
  sourceLedger(): unknown;
  sourceCoordinates: readonly (readonly number[])[] | undefined;
  setupUsageIsolated(dag: unknown): boolean;
  openSourceFreeHost(registry: unknown, values: string, fragment: string | undefined,
    ordered: string | undefined, providers: readonly unknown[]): unknown;
  openCapturedHost(captures: readonly RecoveryCapture[], providers: readonly unknown[]): unknown;
}>;
type ModelAdoption = {
  graph: unknown; scope?: unknown; scopes?: unknown;
  selection?: Readonly<{quantityCapacity?: Readonly<{limits: ModelQuantityLimits}>}>;
};
type ModelAdoptionMember = ModelAdoption & {group: ModelAdoption; originalReadInstallation?: unknown};
type KeyedContentCompiler = (parent: unknown, receipt: object, plan: unknown, graph: unknown) => unknown;
type ModelScopePreparation = (parent: unknown, receipt: object, plan: unknown,
  ...quantities: [] | [tokens: bigint, costUnits: bigint, durationMs: bigint]) => unknown;
type RequestRunRuntime = Readonly<{
  clientProgramReservePublication(run: unknown, prepared: object): unknown;
  clientProgramInstalledManagedRunCompilationOriginal(run: unknown, prepared: object): unknown;
  clientProgramPrepareRequestCaptureModuleBody?(parent: unknown, receipt: object, plan: unknown, invocation?: unknown): unknown;
  clientProgramAdoptRequestCapturePreparation?(parent: unknown, identity: unknown): unknown;
  clientProgramAdoptRequestProgramPreparation?(parent: unknown, identity: unknown): unknown;
  clientProgramPrepareRequestModelsReadScopesWithPlannedQuantities?: ModelScopePreparation;
  clientProgramPrepareRequestModelsReadScopes?: ModelScopePreparation;
  clientProgramPrepareRequestModelsReadScopesWithQuantities?: ModelScopePreparation;
  clientProgramPrepareRequestModelReadScope?: ModelScopePreparation;
  clientProgramPrepareRequestModelReadScopeWithQuantities?: ModelScopePreparation;
  clientProgramCompleteRequestModelPreparation?(parent: unknown, receipt: object, plan: unknown): unknown;
  clientProgramAdoptRequestModelsPreparation?(parent: unknown, identity: unknown, scopes: unknown): unknown;
  clientProgramAdoptRequestModelPreparation?(parent: unknown, identity: unknown, scope: unknown): unknown;
  clientProgramCompleteRequestSerializationPreparation?(parent: unknown, receipt: object, plan: unknown): unknown;
  clientProgramCompleteRequestContentPreparation?(parent: unknown, receipt: object, identity: unknown, plan: unknown): unknown;
  clientProgramAdoptRequestContentPreparation?(parent: unknown, identity: unknown): unknown;
  clientProgramPreparationBorrowSibling(holder: unknown): unknown;
  clientProgramPrepareRequestSubmittedIntent(parent: unknown, receipt: object, value: RequestSnapshot): unknown;
  clientProgramFinishRequestSubmittedIntent(parent: unknown, receipt: object): unknown;
  clientProgramSelectInstalledSourceInput(prepared: object, request: unknown, stage: number, sourceIndex: number): unknown;
  clientProgramComposedInferModelLedgerBytes?(bounds: unknown): unknown;
}>;
type SourceOccurrenceRuntime = Readonly<{
  clientProgramInstalledEffectManagedSourceOccurrence?(run: unknown, prepared: object, request: object, index: number): unknown;
  clientProgramInstalledManagedSourceOccurrence?(run: unknown, prepared: object, request: object, index: number): unknown;
  clientProgramInstalledEffectManagedOperationPlan?(run: unknown, prepared: object, request: unknown): unknown;
}>;
type EffectMaterialFeatures = readonly [boolean, boolean, boolean, boolean, boolean, boolean, boolean];
type RetainedEffectMaterials = Readonly<{
  request: object; wire: string; runDefinitionCid: string; compilation: unknown; identity: unknown;
  environment: unknown; features: EffectMaterialFeatures; value: object & Readonly<{then?: never}>;
}>;
type EffectMaterialWire = Readonly<{wire: string}>;
type EffectMaterialMethod = 'clientProgramIssueRequestEffectPreparedOriginal' |
  'clientProgramIssueRequestEffectRunMaterials' | 'clientProgramAdmitRequestEffectRunMaterialsWithCompilation';
type EffectScopePreparation = (parent: unknown, receipt: object, plan: object,
  ...quantities: [] | [tokens: bigint, costUnits: bigint, durationMs: bigint]) => unknown;
type EffectBorrowMethods = NonNullable<OrdinarySourceRequestState['effectBorrowMethods']> &
  Readonly<{
    clientProgramEffectPreparationInputRead(holder: unknown): object | undefined;
    clientProgramIssueRequestEffectPreparedOriginal?(parent: unknown, receipt: object,
      prepared: object, compilation: unknown): unknown;
    clientProgramIssueRequestEffectRunMaterials?(parent: unknown, receipt: object,
      prepared: object, allowed: unknown, definition: unknown, identity: unknown): unknown;
    clientProgramAdmitRequestEffectRunMaterialsWithCompilation?(parent: unknown, receipt: object,
      prepared: object, wire: string, runDefinitionCid: string, compilation: unknown, identity: unknown,
      textTime: boolean, veca: boolean, rela: boolean, sga: boolean, tea: boolean,
      calendar: boolean, textRank: boolean, environment: unknown): unknown;
    clientProgramEffectPreparationInputSibling?(holder: unknown): unknown;
    clientProgramBorrowRequestEffectPlanInput?(parent: unknown, receipt: object, staticOnly: boolean): unknown;
    clientProgramPrepareRequestEffectKeyedPlan?(parent: unknown, receipt: object, keyed: unknown,
      admission: unknown, declarations: readonly unknown[]): unknown;
    clientProgramReserveRequestEffectOriginalMaterial?(parent: unknown, receipt: object, prepared: object,
      count: number, wireAt: (index: number) => string): unknown;
    clientProgramPrepareRequestEffectModelReadScope?: EffectScopePreparation;
    clientProgramPrepareRequestEffectModelReadScopeWithQuantities?: EffectScopePreparation;
    clientProgramPrepareRequestEffectModelsReadScopes?: EffectScopePreparation;
    clientProgramPrepareRequestEffectModelsReadScopesWithQuantities?: EffectScopePreparation;
    clientProgramCompleteRequestEffectPreparation?(parent: unknown, receipt: object, plan: object): unknown;
    clientProgramAdoptRequestEffectPreparation?(parent: unknown, identity: unknown): unknown;
    clientProgramAdoptRequestEffectModelPreparation?(parent: unknown, identity: unknown, scope: unknown): unknown;
    clientProgramAdoptRequestEffectModelsPreparation?(parent: unknown, identity: unknown, scopes: unknown): unknown;
    clientProgramPrepareRequestEffectKeyedOriginal?(parent: unknown, receipt: unknown, plan: unknown,
      compilation: unknown, compiled: unknown, definition: unknown, keyedPlan: unknown, keyed: unknown): unknown;
  }>;
type State = OrdinarySourceRequestState & OrdinaryModelMaterialsState & {
  context: Readonly<{
    runtime: SourceOccurrenceRuntime & RequestComputationRuntime & RequestEffectExplanationRuntime &
      RequestModelGraphRuntime & RequestRunRuntime & Partial<EffectBorrowMethods> &
      Parameters<typeof checkedPreparation>[0];
    environment?: unknown; preparedEnvironment?: unknown;
  }>;
  effectBorrowMethods?: EffectBorrowMethods;
  effectKeyedPlan?: unknown;
  effectMaterials?: RetainedEffectMaterials;
  effectPlan?: unknown;
  contentPreparation?: RetainedContentPreparation;
  modelSourceCoordinates?: readonly ModelCoordinate[];
  sourceFreeMaxWork?: number;
  staticModelOccurrences?: readonly unknown[];
  staticModelGraphs?: unknown[];
  staticModelExecutions?: unknown[];
  recovery?: ModelRecovery & {childrenPending(): boolean; model?: RecoveryModel; modelView?: RecoveryView};
};
type Producer = SourceProducerCustody & {kind?: string; body?: object; preparation?: State};
type Run = OrdinarySourceRun<Producer> & {closed?: boolean; keyedPreparation?: KeyedEffectPreparation};
type RegisteredRun = Run & {prepared: object; producer: Producer};
type RequestRequirements = Parameters<typeof resourceRuntime.retainOrdinaryManagedRun>[1];
type InstalledSource = Readonly<{declaration: unknown}>;
type Bundle = Readonly<{sources: readonly InstalledSource[]; dataPath?: string}>;
type Context = State['context'];
type OriginalContracts = Readonly<{
  moon: Context['runtime']; admission: unknown; contracts?: Readonly<{values: string; expression: string; ordered: string}>;
}>;
type Originals = Readonly<{
  installation?: Readonly<{
    authorization?: Readonly<{observe?: unknown}>;
    sequenceContractOriginal?: OriginalContracts;
  }>;
}>;
type Callbacks<Original extends Originals> = Readonly<{
  validator(originals: Original): unknown;
  retainedValidator?(originals: Original): unknown;
  borrowSourceInitializationMaterial?(originals: Original): unknown;
  preparationContext?(originals: Original): Context | undefined;
  request?(originals: Original, prepared: object): object;
  retireInitialPreparation?(originals: Original, prepared: unknown): undefined;
  prepare?(originals: Original, view: Readonly<{assertCurrent(): void}>): unknown;
  read?(originals: Original): Bundle;
  requirements?(originals: Original, prepared: object): RequestRequirements;
  effectRequirements?(originals: Original, prepared: object, operationPlan: object): RequestRequirements;
  mockRequirements?(originals: Original, prepared: object, model: unknown): RequestRequirements;
  contentRequirements?(originals: Original, prepared: object, content: unknown): RequestRequirements;
  intent?(originals: Original, view: Readonly<{assertCurrent(): void}>, body: object): string;
}>;
type InstalledPreparation = Readonly<{originals: unknown; source: boolean; current(): void}>;
type CloseStatus = Readonly<{pending: boolean}>;

// Existing Source/Compute responsibility, using real ordinary Node allocation
// and FileHandles rather than a startup-wide provenance proof. Actual Account
// checks stay at the Source consumer; this view grants no read or Model use.
const installations = new WeakMap<object, InstalledPreparation>();
const noNativeFileReadDeclarations = Object.freeze([]);
const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};
const pending = (value: unknown) => {
  const field = value !== null && typeof value === 'object'
    ? Object.getOwnPropertyDescriptor(value, 'pending') : undefined;
  return field === undefined || !Object.hasOwn(field, 'value') || field.value !== false;
};

function immutablePolicySubject<Value>(value: Value) {
  if (value !== null && typeof value === 'object') {
    for (const item of Object.values(value)) immutablePolicySubject(item);
    Object.freeze(value);
  }
  return value;
}

export function assertOrdinarySourcePreparationCurrent(view: unknown, originals: unknown, source: boolean) {
  const state = installations.get(view as object);
  if (state === undefined || state.originals !== originals || state.source !== source) {
    fail('ForeignInstalledSourcePreparation');
  }
  state.current();
}

export async function prepareOrdinarySourceManagedInstallation<Original extends Originals>(
  originals: Original, callbacks: Callbacks<Original>, source: boolean) {
  return prepareOrdinaryManagedInstallation(originals, callbacks, source, false);
}

// Same ordinary Source owner, but the installed Connector supplies its real
// per-occurrence reader. It cannot borrow the Mock document read or its bytes.
// The fixed Host calls this after retaining the actual Project preparation.
export async function prepareOrdinaryProjectSourceManagedInstallation<Original extends Originals>(
  originals: Original, callbacks: Callbacks<Original>) {
  return prepareOrdinaryManagedInstallation(originals, callbacks, true, true);
}

async function prepareOrdinaryManagedInstallation<Original extends Originals>(
  originals: Original, callbacks: Callbacks<Original>, source: boolean, project: boolean) {
  const diagnostic = diagnosticObserver(originals.installation?.authorization?.observe);
  const reportCapacityRefusal = (cause: unknown) => {
    const capacity = requestProgramCapacityRefusal(cause);
    if (capacity !== undefined) diagnostic('preparation_capacity_refused', capacity);
  };
  let closing = false, closed = false, bundle: Bundle | undefined, flight: Promise<CloseStatus> | undefined, checkingBundle = false;
  const receipts = new WeakMap<object, Producer>(), producers = new Set<Producer>(), runs = new WeakMap<object, Run>();
  // The existing live inventory owns producers. Request lookup retains only
  // a weak reference; a held retired Request cannot keep its payload alive or
  // be rebound to another producer after its original owner has retired.
  const requestProducers = new WeakMap<object, WeakRef<Producer>>();
  // Exact Prepared lookup is provenance, not a second strong payload root.
  // The live inventory owns each record until its actual retirement.
  const liveRuns = new Set<Run>();
  const pendingRunRegistrations = new Set<object>();
  const retiredRuns = new WeakMap<object, object>();
  const retireInitialPreparation = (prepared: unknown) => callbacks.retireInitialPreparation!(originals, prepared);
  const borrowSourceInitialization = callbacks.borrowSourceInitializationMaterial;
  const {retainSourceInitializationMaterial, releaseFinishedProducer, producerForRequest} =
    createOrdinarySourceProducerCustody({originals, callbacks, borrowSourceInitialization,
      receipts, producers, requestProducers, fail,
      get closing() { return closing; }, get closed() { return closed; }});
  const current = () => {
    if (closing || closed) fail('SourceManagedPreparationUnavailable');
    callbacks.validator(originals);
    if (bundle !== undefined && !checkingBundle) {
      // The original metadata view itself calls this current fence. Reentry
      // keeps the Host check above, without recursively reading that same
      // view forever. The outer read still verifies its exact retained pair.
      checkingBundle = true;
      try {if (callbacks.read!(originals) !== bundle) fail('ForeignInstalledMockPreparation');}
      finally {checkingBundle = false;}
    }
  };
  const producerFor = (receipt: object) => {
    const producer = receipts.get(receipt);
    if (producer === undefined) fail('ForeignInstalledSourceProducer');
    return producer;
  };
  const status = () => Object.freeze({pending: !closed});
  const {captureReader, closeChild, readBytes} = createOrdinarySourceReaders({
    current, pending, fail, get bundle() { return bundle; }});
  const {retainedRunCurrent, publicationRunFor, runFor, prepareRun} = createOrdinarySourceRunCustody({
    originals, callbacks, runs, liveRuns, receipts, retiredRuns, pendingRunRegistrations,
    producerForRequest, current, fail, get closed() { return closed; }});
  const {originalTimedInvocation, prepareOriginalExplanation, disposeOriginalExplanation,
    cleanupOriginalRequestInput, beginProducer, requestInput, requestSnapshot} = createOrdinarySourceRequestCustody<Original, Run>({originals, current, fail,
      callbacks, receipts, producers, runs, liveRuns, retainSourceInitializationMaterial, retainedRunCurrent,
      releaseFinishedProducer, producerFor, producerForRequest, requestProducers, reportCapacityRefusal,
      get view(): Parameters<typeof createOrdinarySourceRequestCustody<Original, Run>>[0]['view'] { return view; },
      get closing() { return closing; }, get closed() { return closed; }});
  const {reserveModelRecovery, restoreModelOriginal, modelMaterials} =
    createOrdinarySourceModelMaterials({current, producerForRequest, fail, checked, checkedRequestProgramPreparation, runtimeCore});
  function constructEffectMaterials(prepared: object, request: object, method: EffectMaterialMethod, args: readonly unknown[]) {
    // Each private caller has just run its one original current fence.
    const producer = producerForRequest(request), state = producer?.preparation;
    if (state?.preparationFailed) throw state.preparationFailure;
    if (state === undefined || state.prepared !== prepared || state.compilationKind !== 'effectful' ||
        state.holder === undefined || state.preparing || state.adopting ||
        state.effectBorrowMethods?.clientProgramEffectPreparationInputRead(state.holder) !== prepared) {
      fail('ForeignInstalledSourceProducer');
    }
    const moon = state.context.runtime, construct = state.effectBorrowMethods![method];
    const issue = moon.clientProgramRequestProgramModuleIssueCode;
    if (typeof construct !== 'function' || typeof issue !== 'function') fail('NodeManagedRunRuntimeUnavailable');
    return constructRequestDomain(state, () => {
      const result = checkedRequestProgramPreparation(moon, Reflect.apply(construct, moon,
        [state.parent, producer!.receipt, prepared, ...args,
          ...(method === 'clientProgramAdmitRequestEffectRunMaterialsWithCompilation'
            ? [state.context.environment] : [])]), issue);
      current();
      if (producer!.finished || producer!.preparation !== state || state.prepared !== prepared ||
          state.effectBorrowMethods!.clientProgramEffectPreparationInputRead(state.holder) !== prepared) {
        fail('ForeignInstalledSourceProducer');
      }
      return result;
    });
  }
  function registerRequestRun(run: RegisteredRun, construct: () => unknown) {
    // Synchronous reentry must see the same duplicate/capacity reservation
    // before Core adoption. This transient set owns no native Resource.
    if (runs.has(run.prepared) || pendingRunRegistrations.has(run.prepared) ||
        run.producer.liveRuns === Number.MAX_SAFE_INTEGER ||
        liveRuns.size + pendingRunRegistrations.size >= 4096) fail('ForeignInstalledSourceProducer');
    pendingRunRegistrations.add(run.prepared);
    try {
      run.value = construct();
      // Nothing callbackful follows the returned native original before its
      // existing live bag owns cleanup. Current is checked by later consumers.
      run.producer.liveRuns++;
      runs.set(run.prepared, run); liveRuns.add(run);
      return run;
    } finally {pendingRunRegistrations.delete(run.prepared);}
  }
  const view = Object.freeze({
    assertCurrent: current,
    ...requestInput,
    // Only the installed Host supplies this Journal-retained opaque original.
    // It is a new physical-process input lifetime for the SAME logical Request,
    // not an SDK snapshot publication, semantic issuer or physical read grant.
    retainModelRecovery(request: object, identity: object,
        definition: NonNullable<State['recovery']>['definition'], assertRecoveryCurrent: () => void,
        childrenPending: () => boolean) {
      if (request === null || typeof request !== 'object' || requestProducers.has(request) ||
          typeof assertRecoveryCurrent !== 'function' ||
          typeof childrenPending !== 'function') fail('ForeignInstalledSourceProducer');
      const receipt = beginProducer(undefined, (state, original, assertCurrent, ownChildrenPending) => {
        openRequestPreparation(state, original, (() => {assertCurrent(); assertRecoveryCurrent();}) as () => undefined,
          () => ownChildrenPending() || childrenPending());
        return true;
      });
      const producer = producerFor(receipt), state = producer.preparation;
      if (state === undefined) fail('NodeLocalPreparationAdmissionUnavailable');
      state.recovery = {request: identity, definition, restored: undefined,
        assertCurrent: assertRecoveryCurrent, childrenPending};
      state.compilationFamily = 'model-recovery';
      producer.request = request;
      requestProducers.set(request, new WeakRef(producer));
      return Object.freeze({receipt});
    },
    restoreModelOriginal,
    modelRecoveryLedger(prepared: object, request: object): unknown {
      current();
      const producer = producerForRequest(request), state = producer?.preparation, recovery = state?.recovery;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (recovery?.restored?.prepared !== prepared || state!.prepared !== prepared ||
          state!.preparing || state!.adopting) fail('ForeignInstalledSourceProducer');
      const control = recovery.model?.control ?? runtimeCore(state!.context.runtime).publicationControl;
      if (typeof control.checkedClientRequestModelRecoveryLedger !== 'function') fail('NodeManagedRunRuntimeUnavailable');
      return control.checkedClientRequestModelRecoveryLedger(
        state!.parent, producer!.receipt, recovery!.request, recovery!.definition);
    },
    prepareModelRecoveryPlan(prepared: object, request: object, plan: RecoveryPlan,
        selected: RecoverySelection, model: RecoveryModel): RecoveryView {
      current();
      const producer = producerForRequest(request), state = producer?.preparation, recovery = state?.recovery;
      if (state?.preparationFailed) throw state.preparationFailure;
      const restored = recovery?.restored, control = model?.control, compiled = plan?.compiled,
        definition = plan?.runDefinition, graph = selected?.graph, budget = model?.budget;
      const plural = Array.isArray(graph), members = (plural ? model?.components : [model]) as readonly RecoveryMember[] | undefined,
        selections = plural ? selected?.components : [selected];
      if (restored === undefined || state!.prepared !== prepared || restored.prepared !== prepared ||
          state!.compilationFamily !== 'model-recovery' || state!.preparing || state!.adopting ||
          selected?.restoredRun !== restored || restored.compiled !== compiled ||
          restored.runDefinition !== definition || recovery!.definition !== definition ||
          restored.graph !== graph || model?.prepared !== prepared || model.selection !== selected ||
          model.compiled !== compiled || model.runDefinition !== definition || model.graph !== graph ||
          model.closed || model.scopeFinished || budget === undefined || control === undefined ||
          !Array.isArray(members) || members.length === 0 || !Array.isArray(selections) ||
          members.length !== selections.length || plural && members.length !== graph.length ||
          members.some((member, index) => member?.selection !== selections[index] ||
            member.graph !== (plural ? graph[index] : graph) || member.budget === undefined ||
            member.selectedBounds === undefined || member.scope !== undefined && recovery!.model !== model || member.closed ||
            member.control !== control || member.compiled !== compiled || member.runDefinition !== definition) ||
          typeof control.prepareCheckedClientRequestModelRecoveryReadScopes !== 'function' ||
          typeof model.publicationCapacity !== 'function') fail('ForeignInstalledSourceProducer');
      if (recovery!.model !== undefined) {
        if (recovery!.model !== model || recovery!.modelView === undefined) fail('ForeignInstalledSourceProducer');
        recovery!.modelView.assertRuntimeCurrent();
        return recovery!.modelView;
      }
      // This original Host record owns a partial returned Scope before any
      // current callback can fail. No ordinary ManagedRun or module is issued.
      recovery!.model = model;
      const moon = state!.context.runtime, graphs = plural ? graph : [graph];
      const publication = model.publicationCapacity;
      const assertOriginalIdentity = (retiring = false) => {
        if (closed || receipts.get(producer!.receipt) !== producer || !producers.has(producer!) ||
            producer!.finished && !retiring || producer!.preparation !== state || state!.recovery !== recovery ||
            recovery!.restored !== restored || recovery!.model !== model || state!.prepared !== prepared ||
            model.selection !== selected || model.graph !== graph || model.compiled !== compiled ||
            model.runDefinition !== definition || model.control !== control || model.budget !== budget ||
            model.publicationCapacity !== publication || plan.compiled !== compiled || plan.runDefinition !== definition) {
          fail('ForeignInstalledSourceProducer');
        }
      };
      const assertOriginal = () => {
        current();
        assertOriginalIdentity();
        recovery!.assertCurrent();
        assertOriginalIdentity();
      };
      const assertRetainedOriginal = () => {
        // Cancellation revokes new work, not the same retained Read/Scope's
        // retirement duty. A failed finish ends new work before all children
        // retire. Its still-registered producer retains this exact same child.
        assertOriginalIdentity(true);
        callbacks.retainedValidator!(originals);
        assertOriginalIdentity(true);
      };
      try {
        // The legacy nine-field suffix describes read-side allowances, not
        // the selected Model Ledger floor. Preserve both originals: Scope
        // admission uses the stored floor or larger installed envelope, while
        // the existing Read view keeps its original budget unchanged.
        const projectModel = moon.clientProgramComposedInferModelLedgerBytes;
        if (typeof projectModel !== 'function') fail('NodeManagedRunRuntimeUnavailable');
        const modelRetained = [], modelExecution = [];
        for (const member of members) {
          const floor = Reflect.apply(projectModel, moon, [member.selectedBounds]);
          if (!Array.isArray(floor) || floor.length !== 2 ||
              floor.some(value => typeof value !== 'bigint' || value < 0n)) fail('InvalidHostRuntimeResult');
          modelRetained.push(member.budget.modelRetainedBytes > floor[0] ? member.budget.modelRetainedBytes : floor[0]);
          modelExecution.push(member.budget.modelExecutionBytes > floor[1] ? member.budget.modelExecutionBytes : floor[1]);
        }
        const scopes = control.prepareCheckedClientRequestModelRecoveryReadScopes(
          state!.parent, producer!.receipt, recovery!.request, definition, prepared, compiled, graphs,
          members.map(member => member.selectedBounds),
          modelRetained, modelExecution,
          members.map(member => member.budget.readRetainedBytes),
          members.map(member => member.budget.readExecutionBytes),
          budget.maxReservations, budget.maxHoldings, budget.maxDelegations,
          selected.quantityCapacity?.limits);
        // Retain the complete native return before examining it or calling out.
        model.scopes = scopes;
        if (!Array.isArray(scopes) || scopes.length !== members.length) fail('InvalidHostRuntimeResult');
        Object.freeze(scopes);
        model.scope = scopes[0];
        for (let index = 0; index < members.length; index++) members[index].scope = scopes[index];
        assertOriginal();
        const componentViews = Object.freeze(members.map((member, index) => {
          const scope = scopes[index], selection = selections[index], memberGraph = graphs[index],
            memberBudget = member.budget, physical = member.originalReadInstallation;
          const assertMemberIdentity = () => {
            if (member.closed || member.scopeFinished || member.scope !== scope ||
                member.selection !== selection || member.graph !== memberGraph || member.budget !== memberBudget ||
                member.originalReadInstallation !== physical || model.scopes !== scopes || scopes[index] !== scope) {
              fail('ForeignInstalledModelRecoveryScope');
            }
          };
          const currentMember = () => {assertOriginal(); assertMemberIdentity();};
          const publicationCapacity = () => {currentMember(); return Reflect.apply(publication, model, []);};
          // Startup retains the same physical adapter grant as a fresh
          // installed read. The native allowance stays in the Model Scope for
          // its original attempts, evidence and output.
          const startup = physical === undefined ? memberBudget : inferOriginalReadStartupCapacity(physical);
          const fields = {selection, control, compiled, runDefinition: definition, scope,
            publicationCapacity, assertRuntimeCurrent: currentMember,
            readRetainedBytes: memberBudget.readRetainedBytes, readExecutionBytes: memberBudget.readExecutionBytes,
            modelRetainedBytes: startup.modelRetainedBytes, modelExecutionBytes: startup.modelExecutionBytes,
            ...(physical === undefined ? {} : {nodeInstallation: physical.nodeInstallation, metadataInstallation: physical})};
          const prepareRead = () => {
            currentMember();
            if (Object.hasOwn(member, 'readFailure')) throw member.readFailure;
            if (!member.taken || member.readAttempted) fail('ForeignInstalledModelRecoveryScope');
            member.readAttempted = true;
            try {
              member.read = physical === undefined
                ? control.prepareCheckedClientInferOriginalRead(compiled, definition, memberGraph, scope, memberBudget)
                : control.prepareCheckedClientInferNodeReadLayout(compiled, definition, memberGraph, scope, physical.nodeInstallation);
              return Object.freeze({...fields, read: member.read});
            } catch (cause) {member.readFailure = cause; throw cause;}
          };
          return Object.freeze({...fields,
            retain() {
              currentMember();
              if (member.taken || member.readAttempted) fail('ForeignInstalledModelRecoveryScope');
              member.taken = true;
            },
            prepareRead,
            restoreRead(input: Readonly<{savedScope?: unknown}> | undefined) {
              currentMember();
              if (input?.savedScope === undefined ||
                  typeof control.startCheckedClientOriginalRestoredComposedInferExecution !== 'function') {
                fail('InstalledModelRecoveryRuntimeUnavailable');
              }
              return prepareRead();
            },
            async retire() {
              if (member.closed && member.scopeFinished) return true;
              assertRetainedOriginal();
              assertMemberIdentity();
              retireNodeInferOriginalRead(member);
              member.read = undefined;
              if (plural) return true; // The original group finishes after all reads.
              if (control.finishCheckedClientInferOriginalReadScope(compiled, definition, memberGraph, scope, true) !== true) return false;
              member.scopeFinished = member.closed = true;
              return true;
            }});
        }));
        const openHost = (captures: readonly RecoveryCapture[], registry: unknown, values: string,
            fragment: string | undefined, ordered: string | undefined, providers: readonly unknown[]) => {
          assertOriginal();
          if (!model.taken || model.hostAttempted || !Array.isArray(captures) || !Array.isArray(providers) ||
              captures.length !== moon.clientProgramAcquisitionCount(prepared)) fail('ForeignInstalledModelRecoveryScope');
          model.hostAttempted = true;
          return control.openCheckedClientRequestModelRecoveryHost(state!.parent, producer!.receipt,
            recovery!.request, definition, prepared, captures.map(value => value.capture.source()),
            registry, values, fragment, ordered, providers);
        };
        const hostFields = {
          prepareSource<Value extends object>(occurrence: SourceOccurrence, construct: (input: unknown) => Value): Value {
            const currentSource = () => {
              assertOriginal();
              if (state!.preparationFailed) throw state!.preparationFailure;
              if (members.some(member => !member.taken || member.closed || member.scopeFinished)) {
                fail('ForeignInstalledModelRecoveryScope');
              }
            };
            currentSource();
            if (typeof construct !== 'function' || !view.modelSourceCoordinates(prepared, request)!.some(coordinates =>
                  (['stage', 'input', 'task'] as const).every((name, index) => occurrence?.[name] === coordinates[index]))) {
              fail('ForeignInstalledModelRecoveryScope');
            }
            // The same retained material funds this metadata-only constructor
            // before it runs. There is no fresh ManagedRun or physical read.
            reserveModelRecovery(producer!, state!, 1, () => recovery!.original!.materialsWire, 1);
            return constructRequestDomain(state!, () => {
              currentSource();
              const selectedSource = checked(moon.clientProgramSelectInstalledSourceInput(
                prepared, recovery!.request, occurrence.stage, occurrence.input));
              currentSource();
              const result = construct(selectedSource);
              if (result === null || typeof result !== 'object' || typeof (result as {then?: unknown}).then === 'function') {
                fail('ForeignInstalledModelRecoveryScope');
              }
              currentSource();
              return result;
            });
          },
          sourceLedger() {return view.modelRecoveryLedger(prepared, request);},
          setupUsageIsolated(dag: unknown) {
            assertOriginal();
            return control.checkedClientRequestModelRecoveryUsageIsolated(state!.parent, producer!.receipt,
              recovery!.request, definition, dag) === true;
          },
          openSourceFreeHost(registry: unknown, values: string, fragment: string | undefined,
              ordered: string | undefined, providers: readonly unknown[]) {
            return openHost([], registry, values, fragment, ordered, providers);
          },
          openCapturedHost(captures: readonly RecoveryCapture[], providers: readonly unknown[]) {
            const contracts = originalsInstallationContracts();
            return openHost(captures, contracts.admission, contracts.contracts!.values, contracts.contracts!.expression, contracts.contracts!.ordered, providers);
          },
        };
        // Reuse this installation's original contract/codec bodies. They are
        // immutable construction inputs, never reconstructed from a profile ID.
        function originalsInstallationContracts() {
          const contracts = originalsInstallation!.sequenceContractOriginal;
          if (contracts === undefined || contracts.moon !== moon) fail('NodeManagedRunRuntimeUnavailable');
          return contracts;
        }
        const originalsInstallation = originals.installation;
        recovery!.modelView = plural ? Object.freeze({selection: selected, control, compiled, runDefinition: definition,
          components: componentViews, scopes, assertRuntimeCurrent: assertOriginal, ...hostFields,
          get sourceCoordinates() {return view.modelSourceCoordinates(prepared, request);},
          retain() {assertOriginal(); for (const original of componentViews) original.retain(); model.taken = true;},
          async retire() {
            if (model.closed && model.scopeFinished) return true;
            assertRetainedOriginal();
            for (const original of componentViews) await original.retire();
            if (!finishNodeInferOriginalReadScopes(model as unknown as Parameters<typeof finishNodeInferOriginalReadScopes>[0])) return false;
            model.closed = true; return true;
          }}) : Object.freeze({...componentViews[0], ...hostFields,
          get sourceCoordinates() {return view.modelSourceCoordinates(prepared, request);}});
        return recovery!.modelView;
      } catch (cause) {
        state!.preparationFailed = true; state!.preparationFailure = cause;
        throw cause;
      }
    },
    retainRequestInput(request: object, intent: unknown, captured?: unknown, materialWire?: string) {
      if (request === null || typeof request !== 'object' || requestProducers.has(request) ||
          (intent === undefined) === (captured === undefined) ||
          materialWire !== undefined && (typeof materialWire !== 'string' || captured !== undefined)) {
        fail('ForeignInstalledSourceProducer');
      }
      let retainIntent: ((parent: unknown, receipt: object, intent: unknown) => unknown) | undefined;
      let intentWire: ((intent: unknown) => unknown) | undefined;
      let reserveMaterial: ((parent: unknown, receipt: object, material: string) => unknown) | undefined;
      const receipt = beginProducer(undefined, (state, original, assertCurrent, childrenPending) => {
        const moon = state.context.runtime;
        if (captured === undefined) {
          retainIntent = Object.getOwnPropertyDescriptor(moon, 'clientProgramRetainRequestSubmittedIntent')?.value;
          intentWire = Object.getOwnPropertyDescriptor(moon, 'clientSubmittedIntentWire')?.value;
          reserveMaterial = Object.getOwnPropertyDescriptor(moon, 'clientProgramReserveRequestRetainedProgramMaterial')?.value;
          if (typeof retainIntent !== 'function' || typeof intentWire !== 'function') {
            fail('NodeManagedRunRuntimeUnavailable');
          }
        }
        openRequestPreparation(state, original, assertCurrent, childrenPending);
        return true;
      });
      const producer = producerFor(receipt), state = producer.preparation;
      try {
        if (state === undefined) fail('NodeLocalPreparationAdmissionUnavailable');
        state.preparing = true;
        if (captured !== undefined) {
          // Only the Host's admitted Checkpoint reconstruction supplies this
          // original capture. Reuse the existing Source snapshot observer and
          // SAME new physical-process Request; issue no intent/CID or epoch.
          const body = view.captureSourceSnapshot(receipt, captured, snapshotClientRequest) as RequestSnapshot;
          freezeInput(body);
          producer.kind = body.kind;
          view.bindSourceSnapshot(receipt, body);
          view.bindSourceRequest(receipt, body, request);
          return Object.freeze({receipt, body});
        }
        const moon = state.context.runtime;
        // Source observes geometry and grows this SAME parent before JSON.parse.
        // Retain the opaque intent itself; no serializer/hash/new identity runs.
        checked(Reflect.apply(retainIntent!, moon, [state.parent, receipt, intent]));
        if (closing || closed || producer.finished || producer.preparation !== state ||
            receipts.get(receipt) !== producer || state.parent === undefined) fail('ForeignInstalledSourceProducer');
        const wire = Reflect.apply(intentWire!, moon, [intent]);
        if (typeof wire !== 'string') fail('InvalidHostRuntimeResult');
        const body = JSON.parse(wire);
        if (materialWire !== undefined && (body.kind === 'program' ||
            body.kind === 'aql' && body.parameters !== null)) {
          if (typeof reserveMaterial !== 'function') fail('NodeManagedRunRuntimeUnavailable');
          checked(Reflect.apply(reserveMaterial, moon, [state.parent, receipt, materialWire]));
          if (closing || closed || producer.finished || producer.preparation !== state ||
              receipts.get(receipt) !== producer || state.parent === undefined) fail('ForeignInstalledSourceProducer');
          const material = JSON.parse(materialWire);
          if (material?.program_format !== 'json' || typeof material.program !== 'string' ||
              material.parameters !== null && typeof material.parameters !== 'string') {
            fail('ForeignInstalledSourceProducer');
          }
          const program = body.kind === 'program' ? JSON.parse(material.program) : undefined;
          const parameters = material.parameters === null ? null : JSON.parse(material.parameters);
          // The canonical intent already binds the complete structured input.
          // Compare ALL metadata, values and exact data Strings once, then
          // retain the material's original field order before the sole native
          // Program checker/compiler. No reissued intent or changed material
          // bytes bypass the later exact Run/compilation binding.
          if ((body.kind === 'program' &&
              canonicalValueJson(program, {dataKeys: true}) !== canonicalValueJson(body.input, {dataKeys: true})) ||
              canonicalValueJson(parameters, {dataKeys: true}) !== canonicalValueJson(body.parameters, {dataKeys: true})) {
            fail('ForeignInstalledSourceProducer');
          }
          // Textual Source keeps its exact frontend input and declarations.
          // Only the already-bound Parameter values regain their original
          // interchange order; the later Common material binder still checks
          // the complete lowered Program, compilation, Request and Run.
          if (body.kind === 'program') body.input = program;
          body.parameters = parameters;
        }
        // Keep the SDK envelope's literal null sentinel. The same native
        // bridge treats only null as absent; undefined is supplied input.
        freezeInput(body);
        producer.kind = body.kind;
        state.snapshot = producer.body = body;
        state.snapshotDocument = wire;
        producer.request = request;
        requestProducers.set(request, new WeakRef(producer));
        return Object.freeze({receipt, body});
      } catch (cause) {
        if (state !== undefined) state.preparing = false;
        producer.finished = true;
        producer.body = producer.request = producer.snapshotPublication = undefined;
        if (state !== undefined) state.snapshot = state.snapshotDocument = undefined;
        try {
          if (state !== undefined) cleanupOriginalRequestInput(state, retireInitialPreparation);
          producer.preparation = undefined;
          releaseFinishedProducer(producer);
        } catch (cleanupCause) {
          throw Object.assign(new Error('NodeLocalPreparationCleanupPending', {cause}),
            {code: 'NodeLocalPreparationCleanupPending', cleanupPending: true, cleanupCause});
        }
        throw cause;
      } finally {
        if (state !== undefined) state.preparing = false;
      }
    },
    ...requestSnapshot,
    observeOriginalCheckOutcome<Value>(request: object, failure: unknown,
        visit: (read: (metadata: readonly unknown[]) => string | undefined) => Value): Value | undefined {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      // No retained original is reconstructed after completion/retirement, or
      // for a foreign failure merely carrying a public-looking error code.
      if (state === undefined || state.parent === undefined || state.preparing ||
          !state.preparationFailed || state.preparationFailure !== failure ||
          state.originalCheckResult === undefined || typeof state.projectOriginalCheck !== 'function') return undefined;
      if (typeof visit !== 'function') fail('InvalidOriginalCheckObservation');
      const parent = state.parent, result = state.originalCheckResult;
      const project = state.projectOriginalCheck, moon = state.context.runtime;
      const assertSame = () => {
        current();
        if (producer!.finished || producer!.request !== request || producer!.preparation !== state ||
            state.parent !== parent || state.originalCheckResult !== result ||
            state.preparing || !state.preparationFailed || state.preparationFailure !== failure) {
          fail('ForeignInstalledSourceProducer');
        }
      };
      // Availability is decided from this SAME failed state before any
      // Source/account/namespace metadata visitor can await or do work.
      assertSame();
      return visit(metadata => {
        if (!Array.isArray(metadata) || metadata.length !== 13) fail('InvalidOriginalCheckObservation');
        assertSame();
        // Preserve the original Result wrapper. Only the typed C bridge may
        // match its terminal; no Err/Option or Error.cause is rebuilt in JS.
        const wire = checked(Reflect.apply(project, moon,
          [parent, producer!.receipt, result, ...metadata]));
        assertSame();
        if (wire !== undefined && typeof wire !== 'string') fail('InvalidOriginalCheckObservation');
        return wire;
      });
    },
    async withOriginalStaticEffectExplanation<Value>(request: object, environment: unknown,
        originalVerifier: VerifyOriginalPolicy | undefined, signal: AbortSignal | undefined, limits: StaticPlanLimits,
        maxWork: number, visit: StaticExplanationVisitor<Value>, modelInstallation?: StaticModelInstallation,
        fileReadDeclarations?: readonly unknown[], debugEntryInstalled = false): Promise<Awaited<Value>> {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.parent === undefined || state.preparing || state.adopting ||
          state.staticPlanRead || state.staticExplanationDelivery !== undefined ||
          limits == null || typeof visit !== 'function' || !Number.isSafeInteger(maxWork) || maxWork < 1 ||
          maxWork > 2147483647) fail('ForeignInstalledSourceProducer');
      const parent = state.parent;
      state.staticExplanationDelivery = visit;
      const assertOriginal = () => {
        current();
        if (producerForRequest(request) !== producer || producer!.preparation !== state ||
            state.parent !== parent || state.staticExplanationDelivery !== visit) {
          fail('ForeignInstalledSourceProducer');
        }
        signal?.throwIfAborted();
      };
      try {
        const wires = await view.fundedPreparation(request, environment, originalVerifier, signal,
          undefined, limits, modelInstallation, fileReadDeclarations, visit, maxWork, debugEntryInstalled);
        assertOriginal();
        const response = await visit(wires as StaticExplanationWires, assertOriginal);
        assertOriginal();
        return response;
      } finally {
        state.staticExplanationDelivery = undefined;
      }
    },
    async fundedPreparation(request: object, environment: unknown, originalVerifier?: VerifyOriginalPolicy,
        signal?: AbortSignal, journal?: RequestJournal, staticPlan?: StaticPlanLimits,
        staticModelInstallation?: StaticModelInstallation, staticFileReadDeclarations?: readonly unknown[],
        staticExplanation?: StaticExplanationVisitor<unknown>, maxWork?: number, debugEntryInstalled = false):
        Promise<FundedRequest | StaticExplanationWires | string | undefined> {
      current();
      const producer = producerForRequest(request);
      const state = producer?.preparation;
      if (state === undefined) return undefined;
      if (!requestPreparationAvailable(state.context)) fail('NodeLocalPreparationAdmissionUnavailable');
      const sourceFreeMaxWork = Object.getOwnPropertyDescriptor(state.context, 'sourceFreeMaxWork')?.value;
      if (Object.hasOwn(state, 'sourceFreeMaxWork')) {
        if (state.sourceFreeMaxWork !== sourceFreeMaxWork) fail('ForeignInstalledSourceProducer');
      } else state.sourceFreeMaxWork = sourceFreeMaxWork;
      if (state.context.environment !== environment || state.adopting || state.preparing ||
          state.staticExplanationDelivery !== staticExplanation ||
          state.parent === undefined ||
          originalVerifier !== undefined && typeof originalVerifier !== 'function' ||
          state.policyVerifierSelected &&
            (state.policyVerifier !== originalVerifier || state.policySignal !== signal)) {
        fail('ForeignInstalledSourceProducer');
      }
      const moon = state.context.runtime;
      // Only the installed static-plan service selects this private read.
      // Capture the same loaded compiler method before policy verification can
      // await. Its token still requires actual original working admission.
      const inspectInstalled = staticPlan !== undefined &&
        typeof Object.getOwnPropertyDescriptor(moon, 'clientProgramCurrentRunView')?.value === 'function';
      const readStaticPlan = staticPlan === undefined ? undefined
        : Object.getOwnPropertyDescriptor(moon, 'clientProgramRequestOriginalStaticPlanWire')?.value;
      const readCheckedStaticPlan = staticPlan === undefined ? undefined
        : Object.getOwnPropertyDescriptor(moon, 'clientProgramReadRequestCheckedStaticPlan')?.value;
      const checkedStaticIssue = staticPlan === undefined ? undefined
        : Object.getOwnPropertyDescriptor(moon, 'clientProgramRequestCheckedStaticPlanIssueCode')?.value;
      const explanationPorts = staticExplanation === undefined ? undefined : [
        'clientProgramReadRequestCheckedStaticEffectExplanation',
        'clientProgramStaticEffectExplanationPlanWire',
        'clientProgramStaticEffectExplanationFactsWire',
        'clientProgramStaticEffectExplanationContextWire',
      ].map(function originalExplanationPort(name) {
        return Object.getOwnPropertyDescriptor(moon, name)?.value;
      });
      if (explanationPorts !== undefined && explanationPorts.some(function missingExplanationPort(port) {
        return typeof port !== 'function';
      })) {
        fail('ClientOperationUnavailable');
      }
      const borrowStaticEffect = staticPlan === undefined ? undefined
        : Object.getOwnPropertyDescriptor(moon, 'clientProgramBorrowRequestEffectPlanInput')?.value;
      const readStaticOccurrences = staticPlan === undefined ? undefined
        : Object.getOwnPropertyDescriptor(moon, 'clientProgramEffectInferOccurrences')?.value;
      const readStaticEffect = staticPlan === undefined ? undefined
        : Object.getOwnPropertyDescriptor(moon, 'clientProgramEffectPreparationInputRead')?.value;
      const returnStaticEffect = staticPlan === undefined ? undefined
        : Object.getOwnPropertyDescriptor(moon, 'clientProgramEffectPreparationInputReturn')?.value;
      const retiringStaticEffect = staticPlan === undefined ? undefined
        : Object.getOwnPropertyDescriptor(moon, 'clientProgramEffectPreparationInputRetirementStarted')?.value;
      if (staticPlan !== undefined) {
        if (state.staticPlanRead || state.holder !== undefined) fail('ForeignInstalledSourceProducer');
        state.staticPlanRead = true;
      }
      // This SAME receipt owns the detached Program/Query and Parameters.
      // Its Core entry retains Source/check/compiler originals and typed
      // failure. No serializer, raw preparation or second parent fallback.
      if ((producer!.kind !== 'program' && producer!.kind !== 'aql') || producer!.body !== state.snapshot) {
        fail('ForeignInstalledSourceProducer');
      }
      if (state.preparationFailed) throw state.preparationFailure;
      if (state.holder === undefined) {
        const contracts = originals.installation!.sequenceContractOriginal;
        if (contracts === undefined || contracts.moon !== moon) fail('ForeignInstalledSourceProducer');
        const parent = state.parent;
        const assertPreparingOriginal = () => {
          if (closing || closed || producer!.finished || producer!.preparation !== state ||
              producer!.request !== request || state.parent !== parent ||
              state.policyVerifier !== originalVerifier || state.policySignal !== signal) {
            fail('ForeignInstalledSourceProducer');
          }
          signal?.throwIfAborted();
        };
        state.policyVerifier = originalVerifier; state.policySignal = signal;
        state.policyVerifierSelected = true;
        state.preparing = true;
        try {
          if (state.compilationKind === undefined) {
            const prepareCheck = moon[producer!.kind === 'program'
              ? 'clientProgramPrepareRequestNativeComputation' : 'clientProgramPrepareRequestSourceComputation'];
            const finishComputation = moon.clientProgramFinishRequestComputation;
            const projectIssue = moon.clientProgramRequestPreparationIssueCode;
            const policyMethods = originalVerifier === undefined ? [] : ([
              'clientProgramPrepareRequestPolicySubjects', 'clientProgramReadRequestPolicySubject',
              'clientProgramBindRequestPolicySubject', 'clientProgramFinishRequestPolicySubjects',
            ] as const).map(name => moon[name]);
            if ([prepareCheck, finishComputation, ...policyMethods].some(method => typeof method !== 'function')) {
              fail('NodeManagedRunRuntimeUnavailable');
            }
            assertPreparingOriginal();
            const valuesMaxRows = Object.getOwnPropertyDescriptor(state.context, 'valuesMaxRows')?.value;
            const originalCheckResult = Reflect.apply(prepareCheck!, moon, [
              parent, producer!.receipt, (producer!.body as RequestSnapshot).input,
              (producer!.body as RequestSnapshot).parameters === undefined ? null : (producer!.body as RequestSnapshot).parameters,
              environment, state.context.preparedEnvironment, valuesMaxRows,
            ]);
            // This failed Request already owns the child and its cleanup.
            // Retain only its actual result until that same owner retires it.
            state.originalCheckResult = originalCheckResult;
            checkedRequestProgramPreparation(moon, originalCheckResult, projectIssue);
            state.originalCheckResult = undefined;
            assertPreparingOriginal();
            if (originalVerifier !== undefined) {
              const [prepareSubjects, readSubject, bindSubject, finishSubjects] = policyMethods;
              const count = checkedRequestProgramPreparation(moon, Reflect.apply(prepareSubjects!, moon,
                [parent, producer!.receipt, environment]), projectIssue) as number;
              if (!Number.isSafeInteger(count) || count < 0 || count > 1024) fail('ClientProgramPreparationFailure');
              let wireBytes = 0;
              for (let index = 0; index < count; index++) {
                assertPreparingOriginal();
                const wire = checkedRequestProgramPreparation(moon, Reflect.apply(readSubject!, moon,
                  [parent, producer!.receipt, environment, index]), projectIssue);
                if (typeof wire !== 'string' || (wireBytes += Buffer.byteLength(wire)) > 1048576) {
                  fail('ClientProgramPreparationFailure');
                }
                const subject = immutablePolicySubject(JSON.parse(wire));
                const policyCid = await originalVerifier(subject, {signal});
                assertPreparingOriginal();
                if (policyCid !== undefined &&
                    (typeof policyCid !== 'string' || !/^sha256:[0-9a-f]{64}$/u.test(policyCid))) {
                  fail('ClientProgramPreparationFailure');
                }
                // Core rechecks the original current capacity after the Host
                // await. An explicit decline still consumes this SAME index.
                checkedRequestProgramPreparation(moon, Reflect.apply(bindSubject!, moon,
                  [parent, producer!.receipt, environment, index, policyCid]), projectIssue);
                assertPreparingOriginal();
              }
              checkedRequestProgramPreparation(moon, Reflect.apply(finishSubjects!, moon,
                [parent, producer!.receipt, environment]), projectIssue);
              assertPreparingOriginal();
            }
            // The supplemented Environment stays inside this SAME check child.
            // Finish still receives the original external Environment/publication.
            state.compilationKind = checkedRequestProgramPreparation(moon, Reflect.apply(finishComputation!, moon,
              [parent, producer!.receipt, environment, state.context.preparedEnvironment]), projectIssue) as string;
            assertPreparingOriginal();
          }
          // Actual captured/Effect Plan construction belongs to its existing
          // Host caller. A logical compiler result cannot select a different
          // parent or claim that an unconstructed Plan is ready.
          if (state.compilationKind === 'effectful') {
            if (staticPlan !== undefined) {
              if (typeof borrowStaticEffect !== 'function' || typeof readStaticOccurrences !== 'function' ||
                  typeof readStaticEffect !== 'function' || typeof returnStaticEffect !== 'function' ||
                  typeof retiringStaticEffect !== 'function' ||
                  explanationPorts === undefined &&
                    (typeof readCheckedStaticPlan !== 'function' || typeof checkedStaticIssue !== 'function')) {
                fail('ClientOperationUnavailable');
              }
              // Reserve this metadata purpose before constructing captured
              // method/occurrence/graph vectors. Retain the nominal token
              // before any following callback or fallible namespace read.
              state.holder = checked(Reflect.apply(borrowStaticEffect, moon,
                [state.parent, producer!.receipt, true]));
              // Install the original cleanup immediately. Later optional
              // method capture can fail without stranding this exact holder.
              state.effectBorrowMethods = Object.freeze({
                clientProgramEffectPreparationInputRead: (...args) => Reflect.apply(readStaticEffect, moon, args),
                clientProgramEffectPreparationInputReturn: (...args) => Reflect.apply(returnStaticEffect, moon, args),
                clientProgramEffectPreparationInputRetirementStarted: (...args) => Reflect.apply(retiringStaticEffect, moon, args),
              });
            }
            if (staticPlan === undefined) {
              // The actual typed Effect borrow reserves construction on this SAME
              // Request. Never cast it to a Program borrow or select a new Root.
              const names: (keyof EffectBorrowMethods)[] = ['clientProgramBorrowRequestEffectPlanInput',
                'clientProgramEffectPreparationInputRead', 'clientProgramEffectPreparationInputReturn',
                'clientProgramEffectPreparationInputSibling', 'clientProgramEffectPreparationInputRetirementStarted',
                'clientProgramCompleteRequestEffectPreparation', 'clientProgramAdoptRequestEffectPreparation',
                'clientProgramReserveRequestEffectOriginalMaterial'];
              const methods = names.map(name => moon[name]);
              if (methods.some(method => typeof method !== 'function')) fail('NodeManagedRunRuntimeUnavailable');
              // Model is optional for a non-Model installation. Capture each
              // selected original once; later namespace replacement cannot supply
              // a different Scope constructor or adoption method.
              for (const name of (['clientProgramPrepareRequestEffectModelReadScope',
                'clientProgramPrepareRequestEffectModelReadScopeWithQuantities',
                'clientProgramAdoptRequestEffectModelPreparation',
                'clientProgramPrepareRequestEffectModelsReadScopes',
                'clientProgramPrepareRequestEffectModelsReadScopesWithQuantities',
                'clientProgramAdoptRequestEffectModelsPreparation',
                'clientProgramPrepareRequestEffectKeyedPlan',
                'clientProgramPrepareRequestEffectKeyedOriginal',
                'clientProgramIssueRequestEffectPreparedOriginal',
                'clientProgramIssueRequestEffectRunMaterials',
                'clientProgramAdmitRequestEffectRunMaterialsWithCompilation'] as const)) {
                names.push(name);
                methods.push(Object.getOwnPropertyDescriptor(moon, name)?.value);
              }
              state.effectBorrowMethods = Object.freeze(Object.fromEntries(names.map((name, index) =>
                [name, typeof methods[index] === 'function'
                  ? (...args: unknown[]) => Reflect.apply(methods[index]!, moon, args) : undefined]))) as
                    Readonly<Record<keyof EffectBorrowMethods, unknown>> as EffectBorrowMethods;
              state.holder = checked(state.effectBorrowMethods.clientProgramBorrowRequestEffectPlanInput!(
                state.parent, producer!.receipt, false));
            }
          } else if (state.compilationKind === 'effect_free') {
            // Core retains the original audit/journal under this SAME Request.
            // ProgramCompiled precedes the Plan borrow and optional Facts;
            // publication later reads this original, never seals an empty copy.
            const normalize = Object.getOwnPropertyDescriptor(moon,
              'clientProgramPrepareRequestProgramNormalization')?.value;
            const normalizationIssue = Object.getOwnPropertyDescriptor(moon,
              'clientProgramRequestProgramNormalizationIssueCode')?.value;
            if (typeof normalize !== 'function' || typeof normalizationIssue !== 'function') {
              fail('NodeManagedRunRuntimeUnavailable');
            }
            checkedRequestProgramPreparation(moon,
              Reflect.apply(normalize, moon, [state.parent, producer!.receipt]), normalizationIssue);
            assertPreparingOriginal();
            const authoring = Object.getOwnPropertyDescriptor(moon,
              'clientProgramPrepareRequestProgramAuthoringContext')?.value;
            const authoringIssue = Object.getOwnPropertyDescriptor(moon,
              'clientProgramRequestProgramAuthoringContextIssueCode')?.value;
            if (typeof authoring !== 'function' || typeof authoringIssue !== 'function') {
              fail('NodeManagedRunRuntimeUnavailable');
            }
            state.authoringContextOriginal = checkedRequestProgramPreparation(moon,
              Reflect.apply(authoring, moon, [state.parent, producer!.receipt]), authoringIssue);
            if (state.authoringContextOriginal === undefined) fail('InvalidHostRuntimeResult');
            assertPreparingOriginal();
            // This first borrow exposes only the SAME checked inventory. An
            // effect-free compiler result is not an ordinary Module witness:
            // INFER and Serialization retain their own construction inputs.
            state.holder = checked(moon.clientProgramBorrowRequestProgramPlanInput(
              state.parent, producer!.receipt));
            const prepared = moon.clientProgramPreparationBorrowRead(state.holder) as object | undefined;
            if (prepared === undefined) fail('ForeignInstalledSourceProducer');
            const inferOccurrences = moon.clientProgramComposedInferOccurrences;
            const serializationOccurrences = moon.clientProgramSerializationOccurrences;
            if (typeof inferOccurrences !== 'function' || typeof serializationOccurrences !== 'function') {
              fail('NodeManagedRunRuntimeUnavailable');
            }
            const infers = checked(Reflect.apply(inferOccurrences, moon, [prepared]));
            const serializations = Reflect.apply(serializationOccurrences, moon, [prepared]);
            if (!Array.isArray(infers) || !Array.isArray(serializations)) fail('InvalidHostRuntimeResult');
            // Model owns the mixed constructor borrow too. Its typed Graph
            // and prefix constructors validate the original composition;
            // inventory counts do not authorize an ordinary Pure module.
            state.compilationFamily = infers.length !== 0 ? 'model'
              : serializations.length !== 0 ? 'content' : 'pure';
            if (staticPlan !== undefined && state.compilationFamily !== 'pure' &&
                (staticExplanation === undefined || state.compilationFamily !== 'model')) {
              fail('ClientOperationUnavailable');
            }
            if (staticExplanation !== undefined) state.staticModelOccurrences = infers;
            if (state.compilationFamily !== 'pure') {
              const select = moon[state.compilationFamily === 'model'
                ? 'clientProgramBorrowRequestModelPlanInput' : 'clientProgramBorrowRequestContentPlanInput'];
              if (typeof select !== 'function' || typeof moon.clientProgramPreparationBorrowReturn !== 'function') {
                fail('NodeManagedRunRuntimeUnavailable');
              }
              const selected = checked(Reflect.apply(select, moon, [state.parent, producer!.receipt]));
              // Keep BOTH actual borrows before a read/return can fail. The
              // existing Request retirement owns a failed inventory return.
              state.inventoryHolder = state.holder;
              state.holder = selected;
              if (moon.clientProgramPreparationBorrowRead(selected) !== prepared) {
                fail('ForeignInstalledSourceProducer');
              }
              // Core consumes this borrower before reporting owner retirement.
              // false means the selected owner remains live, not a failed
              // return. A later settlement error must retry the SAME parent,
              // never invoke a consumed borrow token again.
              const inventory = state.inventoryHolder;
              state.inventoryHolder = undefined;
              checked(moon.clientProgramPreparationBorrowReturn(inventory));
            }
            const count = moon.clientProgramAcquisitionCount(prepared);
            if (!Number.isSafeInteger(count) || count < 0) fail('InvalidHostRuntimeResult');
            state.acquisitionCount = count;
            const requiresTime = moon.clientProgramRequiresQueryTime;
            state.requiresQueryTime = typeof requiresTime === 'function'
              ? checked(Reflect.apply(requiresTime, moon, [prepared, 100000, 100000])) as boolean : false;
            if (typeof state.requiresQueryTime !== 'boolean') fail('InvalidHostRuntimeResult');
            if (staticExplanation === undefined && state.compilationFamily === 'pure' && count === 0) {
              prepareOriginalExplanation(state, producer!, contracts, journal, staticPlan, debugEntryInstalled);
            }
            // A timed module needs the actual submission Request and first
            // bound Run. Keep this SAME borrower until that adoption caller.
            if (staticPlan === undefined && state.compilationFamily === 'pure' && count === 0 && !state.requiresQueryTime) {
              checkedRequestProgramPreparation(moon,
                moon.clientProgramPrepareRequestProgramModuleBody(state.parent,
                  producer!.receipt, contracts.admission, state.context.retainedRelationOutput, undefined,
                  state.sourceFreeMaxWork),
                moon.clientProgramRequestProgramModuleIssueCode);
            }
          } else fail('NodeManagedRunPlanUnavailable');
        } catch (cause) {
          reportCapacityRefusal(cause);
          state.preparationFailed = true;
          state.preparationFailure = cause;
          throw cause;
        } finally {state.preparing = false;}
      }
      const prepared = (state.effectBorrowMethods === undefined
        ? moon.clientProgramPreparationBorrowRead(state.holder)
        : state.effectBorrowMethods.clientProgramEffectPreparationInputRead(state.holder)) as object | undefined;
      if (prepared === undefined || state.prepared !== undefined && state.prepared !== prepared) {
        fail('ForeignInstalledSourceProducer');
      }
      if (staticPlan !== undefined) {
        const effectful = state.compilationKind === 'effectful';
        const acquired = (state.acquisitionCount ?? 0) > 0;
        const acquiredPlan = !effectful && acquired && explanationPorts === undefined;
        const acquiredAuthorization = staticPlan.acquiredPlanAuthorization;
        if (acquiredPlan && acquiredAuthorization === undefined) fail('ClientConnectionDenied');
        if (effectful || acquired || explanationPorts !== undefined) {
          if (explanationPorts === undefined &&
              (typeof readCheckedStaticPlan !== 'function' || typeof checkedStaticIssue !== 'function')) {
            fail('ClientOperationUnavailable');
          }
          // Checking has finished and its real nominal borrow is retained.
          // Metadata readers now enter their normal owner stages: no forged
          // `prepared`, preparing-guard bypass or execution-route setup.
          state.prepared = prepared;
          try {
            state.staticModelGraphs = [];
            state.staticModelExecutions = [];
            if (effectful) {
              state.staticModelOccurrences = constructRequestDomain(state, () =>
                checked(Reflect.apply(readStaticOccurrences, moon, [prepared]))) as readonly unknown[];
            }
            const readOriginal = effectful ? state.effectBorrowMethods!.clientProgramEffectPreparationInputRead
              : moon.clientProgramPreparationBorrowRead;
            const assertSelection = () => {
              current(); signal?.throwIfAborted();
              if (producerForRequest(request) !== producer || producer!.finished ||
                  producer!.preparation !== state || state.prepared !== prepared ||
                  Reflect.apply(readOriginal, moon, [state.holder]) !== prepared) {
                fail('ForeignInstalledSourceProducer');
              }
            };
            const assertOriginal = () => {
              assertSelection();
              // Use the original immediate Account decision for each
              // acquired metadata disclosure, including transport delivery.
              if (acquiredPlan) {
                if (acquiredAuthorization!.connection() !== true ||
                    acquiredAuthorization!.accountMetadata() !== true ||
                    acquiredAuthorization!.connection() !== true) fail('ClientConnectionDenied');
                assertSelection();
              }
            };
            assertOriginal();
            const occurrences = effectful || explanationPorts !== undefined
              ? state.staticModelOccurrences! : [];
            for (const occurrence of occurrences) {
              const {execution} = readInstalledModelExecution(moon as typeof moon & ModelExecutionRuntime, prepared, staticModelInstallation!,
                occurrence, (count, wireAt, containers) =>
                  view.prepareModelMaterials(prepared, request, count, wireAt, containers))!;
              // Preserve the original parser return before Graph/current can
              // refuse; no Provider, Scope, Source read or Model invocation.
              state.staticModelExecutions.push(execution);
              assertOriginal();
              state.staticModelGraphs.push(view.prepareModelGraph(prepared, request,
                occurrence, execution, undefined, undefined, staticFileReadDeclarations));
              assertOriginal();
            }
            Object.freeze(state.staticModelGraphs);
            if (explanationPorts !== undefined) {
              return constructRequestDomain(state, function projectOriginalStaticExplanation() {
                const [project, planWire, factsWire, contextWire] = explanationPorts;
                const projection = checked(Reflect.apply(project, moon, [state.parent, producer!.receipt,
                  staticPlan.maxWireBytes, staticPlan.maxNodes, staticPlan.maxDepth,
                  maxWork, state.staticModelGraphs, debugEntryInstalled && !effectful && state.compilationFamily === 'pure']));
                assertOriginal();
                return {plan: Reflect.apply(planWire, moon, [projection]),
                  facts: Reflect.apply(factsWire, moon, [projection]),
                  context: Reflect.apply(contextWire, moon, [projection])};
              });
            }
            return constructRequestDomain(state, () => {
              const wire = checkedRequestProgramPreparation(moon,
                Reflect.apply(readCheckedStaticPlan, moon, [state.parent, producer!.receipt,
                  staticPlan.maxWireBytes, staticPlan.maxNodes, staticPlan.maxDepth,
                  state.staticModelGraphs, inspectInstalled]), checkedStaticIssue);
              assertOriginal();
              if (typeof wire !== 'string') fail('InvalidOriginalStaticPlan');
              if (acquiredPlan) acquiredAuthorization!.retainEgress(assertOriginal);
              return wire;
            });
          } catch (cause) {
            reportCapacityRefusal(cause);
            state.preparationFailed = true; state.preparationFailure = cause;
            throw cause;
          }
        }
        if (typeof readStaticPlan !== 'function') fail('ClientOperationUnavailable');
        const original = state.originalExplanation;
        if (original?.preparation === undefined) fail('ClientOperationUnavailable');
        const wire = constructRequestDomain(state, () => {
          const value = checked(Reflect.apply(readStaticPlan, moon, [original.preparation, inspectInstalled]));
          current();
          if (producerForRequest(request) !== producer || producer!.preparation !== state ||
              state.originalExplanation !== original || typeof value !== 'string') {
            fail('ForeignInstalledSourceProducer');
          }
          return value;
        });
        // No submitted alias, module, invocation or Run was constructed.
        // Existing producer retirement returns the SAME loan and inventory.
        return wire;
      }
      state.prepared = prepared;
      if (!state.parameterMetadataLoaded) {
        state.parametersCursor = checked(moon.clientProgramRequestParametersOriginal(state.parent, producer!.receipt));
        state.parameterMetadataLoaded = true;
      }
      return Object.freeze({kind: state.compilationKind, prepared,
        originalInputs: Object.freeze({environment, parameters: undefined,
          parametersCursor: state.parametersCursor})});
    },
    issueEffectMaterials(prepared: object, request: object, allowed: unknown, definition: unknown,
        identity?: unknown, compilation?: unknown) {
      current();
      if (compilation !== undefined) {
        return constructEffectMaterials(prepared, request, 'clientProgramIssueRequestEffectPreparedOriginal',
          [compilation]) as string;
      }
      return constructEffectMaterials(prepared, request, 'clientProgramIssueRequestEffectRunMaterials',
        [allowed, definition, identity ?? null]) as string;
    },
    captureEffectRunExplanation<Evidence extends EffectPlanEvidence>(prepared: object, request: object, facts: EffectExplanationFacts,
        readEvidence: (budget: number) => Evidence | undefined, journal: RequestJournal, hasIntent: boolean) {
      current();
      assertOriginalClientRequestJournal(journal);
      const budget = journal.originalExplanationContextLimit();
      if (budget === undefined) return undefined;
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      const methods = state?.effectBorrowMethods;
      if (state === undefined || state.prepared !== prepared || facts.prepared !== prepared ||
          state.compilationKind !== 'effectful' || state.holder === undefined ||
          methods === undefined || state.preparing || state.adopting || state.originalExplanation !== undefined ||
          methods.clientProgramEffectPreparationInputRead(state.holder) !== prepared) fail('ForeignInstalledSourceProducer');
      const moon = state.context.runtime;
      const capture = moon.clientProgramTryCaptureEffectRunExplanation;
      const read = moon.clientProgramEffectRunExplanationWires;
      const discard = moon.clientProgramDiscardEffectRunExplanation;
      if (typeof capture !== 'function' || typeof read !== 'function' ||
          typeof discard !== 'function') return undefined;
      const selected = constructRequestDomain(state, () => {
        const {maxNodes, maxDepth} = localContractLimits;
        const scope = checked(capture(state.parent, producer!.receipt, facts.allowed, facts.definition,
          budget, maxNodes, maxDepth, 10000));
        if (scope === undefined) return undefined;
        // Own the cleanup token before any canonical-wire getter or current check.
        const original: NonNullable<State['originalExplanation']> = state.originalExplanation = Object.seal({scope, definition: facts.definition,
          plan: undefined, factsWire: undefined, contextWire: undefined, invocationTemplateWire: undefined,
          offered: false, acknowledged: false, returning: false, databaseClosed: false, journal,
          methods: Object.freeze({returnCapture: discard})});
        const wires = checked(read(scope, facts.definition));
        if (!Array.isArray(wires) || wires.length !== 5 ||
            wires.some(wire => typeof wire !== 'string' || wire.length === 0)) fail('InvalidClientRunExplanationOriginal');
        const [compiledPlanWire, planViewWire, factsWire, contextWire, invocationTemplateWire] = wires;
        current();
        if (producerForRequest(request) !== producer || producer!.preparation !== state ||
            state.prepared !== prepared || state.originalExplanation !== original ||
            methods.clientProgramEffectPreparationInputRead(state.holder) !== prepared) fail('ForeignInstalledSourceProducer');
        original.plan = Object.freeze({compiledPlanWire, planViewWire});
        const evidence = readEvidence(budget);
        // Measure the exact JSON without emitting a new copy. The submitted
        // intent has a fixed 71-byte CID, counted here before the Journal adds it.
        const candidate = Object.freeze({...evidence,
          ...(hasIntent ? {submittedIntentCid: facts.runDefinition.identity} : {})});
        const fits = evidence !== undefined && sourceAliasDataGeometry(candidate).jsonBytes <= BigInt(budget) &&
          Buffer.byteLength(compiledPlanWire) + Buffer.byteLength(planViewWire) + Buffer.byteLength(factsWire) +
            Buffer.byteLength(contextWire) + Buffer.byteLength(invocationTemplateWire) <= budget;
        current();
        if (producerForRequest(request) !== producer || producer!.preparation !== state ||
            state.originalExplanation !== original ||
            methods.clientProgramEffectPreparationInputRead(state.holder) !== prepared) fail('ForeignInstalledSourceProducer');
        if (!fits) return undefined;
        original.factsWire = factsWire;
        original.contextWire = contextWire;
        original.invocationTemplateWire = invocationTemplateWire;
        const ticket = runtimeCore(state.context.runtime).publicationControl.captureOriginalEffectRunPlan(
          original, facts.runDefinition, facts.prepared, evidence);
        return Object.freeze({ticket, evidence});
      });
      if (selected === undefined && state.originalExplanation !== undefined) {
        // The sizing frame and its wires have unwound before this return can
        // restore the original working charge.
        constructRequestDomain(state, () => {
          if (!disposeOriginalExplanation(state, true)) fail('InstalledExplanationAdmissionCleanupPending');
        });
        current();
        if (producerForRequest(request) !== producer || producer!.preparation !== state) fail('ForeignInstalledSourceProducer');
      }
      return selected;
    },
    admitEffectMaterials(prepared: object, request: object, wire: string, runDefinitionCid: string,
        compilation: unknown, identity: unknown, features: readonly unknown[]) {
      current();
      const run = runs.get(prepared), producer = run?.producer ?? producerForRequest(request);
      const state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined || state.prepared !== prepared ||
          state.compilationKind !== 'effectful' || state.preparing || state.holder === undefined ||
          state.effectBorrowMethods?.clientProgramEffectPreparationInputRead(state.holder) !== prepared ||
          !Array.isArray(features) || types.isProxy(features) || features.length !== 7) fail('ForeignInstalledSourceProducer');
      // Fixed scalar locals preserve the exact flags passed through callbacks
      // without allocating the retained snapshot before its funded constructor.
      const f0=features[0], f1=features[1], f2=features[2], f3=features[3],
        f4=features[4], f5=features[5], f6=features[6], environment=state.context.environment;
      if (typeof f0 !== 'boolean' || typeof f1 !== 'boolean' || typeof f2 !== 'boolean' ||
          typeof f3 !== 'boolean' || typeof f4 !== 'boolean' || typeof f5 !== 'boolean' ||
          typeof f6 !== 'boolean') fail('ForeignInstalledSourceProducer');
      const retained = state.effectMaterials;
      if (retained !== undefined) {
        // Immutable codec DATA is not a cached Allow. The actual adopted
        // owner/current fence still runs before each borrowed read.
        if (state.adopting) {
          (retainedRunCurrent as (value: Run | undefined) => void)(run);
          if (run!.request !== request) fail('ForeignInstalledSourceProducer');
        } else if (producerForRequest(request) !== producer) fail('ForeignInstalledSourceProducer');
        if (retained.request !== request || retained.wire !== wire ||
            retained.runDefinitionCid !== runDefinitionCid || retained.compilation !== compilation ||
            retained.identity !== identity || retained.environment !== state.context.environment ||
            state.effectMaterials !== retained) fail('ForeignInstalledSourceProducer');
        if (f0 !== retained.features[0] || f1 !== retained.features[1] || f2 !== retained.features[2] ||
            f3 !== retained.features[3] || f4 !== retained.features[4] || f5 !== retained.features[5] ||
            f6 !== retained.features[6]) fail('ForeignInstalledSourceProducer');
        return retained.value;
      }
      // A new inverse remains preparation-only; no parsing can enter through
      // an adopted or retired Request, or recreate its compiler from DATA.
      const value = constructEffectMaterials(prepared, request, 'clientProgramAdmitRequestEffectRunMaterialsWithCompilation',
        [wire, runDefinitionCid, compilation, identity, f0, f1, f2, f3, f4, f5, f6]) as RetainedEffectMaterials['value'];
      if (state.adopting || producer!.preparation !== state || state.prepared !== prepared ||
          state.context.environment !== environment) fail('ForeignInstalledSourceProducer');
      // The funded codec control reserves this fixed record and seven flags
      // before construction. Typed DATA retains its complete role inventory.
      state.effectMaterials = Object.freeze({request, wire, runDefinitionCid, compilation, identity,
        environment, features: Object.freeze([f0, f1, f2, f3, f4, f5, f6] as const), value});
      return value;
    },
    reserveEffectOriginal(prepared: object, request: object, material: string, installations: readonly EffectMaterialWire[]) {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined || state.prepared !== prepared || state.compilationKind !== 'effectful' ||
          state.holder === undefined || state.preparing || state.adopting ||
          state.effectBorrowMethods?.clientProgramEffectPreparationInputRead(state.holder) !== prepared) {
        fail('ForeignInstalledSourceProducer');
      }
      const moon = state.context.runtime;
      const reserve = state.effectBorrowMethods!.clientProgramReserveRequestEffectOriginalMaterial;
      const issue = moon.clientProgramRequestPreparationIssueCode;
      if (typeof reserve !== 'function' || typeof issue !== 'function') fail('NodeManagedRunRuntimeUnavailable');
      return constructRequestDomain(state, () => {
        checkedRequestProgramPreparation(moon, Reflect.apply(reserve, moon,
          [state.parent, producer!.receipt, prepared, installations.length + 1,
            (index: number) => index === 0 ? material : installations[index - 1].wire]), issue);
        current();
        if (producer!.finished || producer!.preparation !== state || state.prepared !== prepared ||
            state.effectBorrowMethods!.clientProgramEffectPreparationInputRead(state.holder) !== prepared) {
          fail('ForeignInstalledSourceProducer');
        }
      });
    },
    captureModelOriginal<Value>(prepared: object, request: object, construct: (parent: unknown, receipt: object) => Value) {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined || state.prepared !== prepared || state.compilationKind !== 'effect_free' ||
          state.compilationFamily !== 'model' || state.modelCompilation === undefined ||
          state.holder === undefined || state.preparing || state.adopting ||
          typeof construct !== 'function') fail('ForeignInstalledSourceProducer');
      const moon = state.context.runtime;
      if (typeof moon.clientProgramPreparationBorrowRead !== 'function' ||
          moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) fail('ForeignInstalledSourceProducer');
      const compilation = state.modelCompilation;
      return constructRequestDomain(state, () => {
        const value = construct(state.parent, producer!.receipt);
        current();
        if (producer!.finished || producer!.preparation !== state || state.prepared !== prepared ||
            state.modelCompilation !== compilation ||
            moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) fail('ForeignInstalledSourceProducer');
        return value;
      });
    },
    ...modelMaterials,
    prepareEffectKeyedPlan(prepared: object, request: object, keyed: unknown, declarations?: readonly unknown[]) {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined || state.prepared !== prepared ||
          state.compilationKind !== 'effectful' || state.effectBorrowMethods === undefined ||
          state.holder === undefined || state.inventoryHolder !== undefined || state.adopting ||
          state.preparing || state.effectKeyedPlan !== undefined ||
          declarations !== undefined && (!Array.isArray(declarations) || types.isProxy(declarations) || !Object.isFrozen(declarations))) {
        fail('ForeignInstalledSourceProducer');
      }
      const moon = state.context.runtime, contracts = originals.installation!.sequenceContractOriginal;
      const read = state.effectBorrowMethods.clientProgramEffectPreparationInputRead;
      const construct = state.effectBorrowMethods.clientProgramPrepareRequestEffectKeyedPlan;
      const issue = moon.clientProgramRequestProgramModuleIssueCode;
      if (contracts?.moon !== moon || typeof construct !== 'function' || typeof issue !== 'function' ||
          read(state.holder) !== prepared) fail('NodeManagedRunRuntimeUnavailable');
      return constructRequestDomain(state, () => {
        state.effectKeyedPlan = checkedRequestProgramPreparation(moon,
          construct(state.parent, producer!.receipt, keyed, contracts.admission,
            declarations === undefined ? noNativeFileReadDeclarations : declarations), issue);
        current();
        if (producer!.finished || producer!.preparation !== state || state.prepared !== prepared ||
            read(state.holder) !== prepared) fail('ForeignInstalledSourceProducer');
        return state.effectKeyedPlan;
      });
    },
    prepareModelGraph(prepared: object, request: object, occurrence: unknown, execution: unknown, serializationGraph?: unknown,
        constructSerialized?: NonNullable<RequestModelGraphRuntime['clientProgramPrepareRequestSerializedModelGraph']>,
        fileReadDeclarations?: readonly unknown[], admittedProvider?: unknown): unknown {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      const effectful = state?.compilationKind === 'effectful' && state.effectBorrowMethods !== undefined;
      if (state === undefined || state.prepared !== prepared || !effectful && state.compilationFamily !== 'model' ||
          state.holder === undefined || state.inventoryHolder !== undefined || state.adopting ||
          state.preparing || state.modelCompilation !== undefined ||
          state.contentGraph !== serializationGraph) fail('ForeignInstalledSourceProducer');
      const moon = state.context.runtime, contracts = originals.installation!.sequenceContractOriginal;
      const readOriginal = effectful ? state.effectBorrowMethods!.clientProgramEffectPreparationInputRead
        : moon.clientProgramPreparationBorrowRead;
      if (contracts?.moon !== moon || typeof readOriginal !== 'function' ||
          Reflect.apply(readOriginal, moon, [state.holder]) !== prepared) {
        fail('ForeignInstalledSourceProducer');
      }
      if (fileReadDeclarations !== undefined && (!Array.isArray(fileReadDeclarations) ||
          types.isProxy(fileReadDeclarations) || !Object.isFrozen(fileReadDeclarations))) {
        fail('ForeignInstalledSourceProducer');
      }
      const construct = serializationGraph === undefined
        ? admittedProvider !== undefined ? moon.clientProgramPrepareRequestProviderModelGraph
          : fileReadDeclarations === undefined ? moon.clientProgramPrepareRequestModelGraph
          : moon.clientProgramPrepareRequestDeclaredFileModelGraph
        : moon.clientProgramPrepareRequestSerializedModelGraph;
      const issue = moon.clientProgramRequestProgramModuleIssueCode;
      if (typeof construct !== 'function' || typeof issue !== 'function' ||
          serializationGraph !== undefined && typeof constructSerialized !== 'function') fail('NodeManagedRunRuntimeUnavailable');
      return constructRequestDomain(state, () => {
        const result = serializationGraph === undefined
          ? Reflect.apply(construct, moon,
            admittedProvider !== undefined
              ? [state.parent, producer!.receipt, occurrence, execution, contracts.admission,
                admittedProvider, fileReadDeclarations]
              : fileReadDeclarations === undefined
              ? [state.parent, producer!.receipt, occurrence, execution, contracts.admission]
              : [state.parent, producer!.receipt, occurrence, execution, contracts.admission, fileReadDeclarations])
          : constructSerialized!(state.parent, producer!.receipt, occurrence,
            serializationGraph, execution, contracts.admission);
        state.modelGraph = checkedRequestProgramPreparation(moon, result, issue);
        if (state.modelGraph === undefined) fail('NodeManagedRunCompilationUnavailable');
        current();
        if (producer!.finished || producer!.preparation !== state || state.prepared !== prepared ||
            state.contentGraph !== serializationGraph ||
            Reflect.apply(readOriginal, moon, [state.holder]) !== prepared) fail('ForeignInstalledSourceProducer');
        return state.modelGraph;
      });
    },
    prepareModelCompilation(prepared: object, request: object, graph: unknown): unknown {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined) return undefined; // An explicitly separate purpose.
      const multiple = Array.isArray(graph);
      if (multiple && (types.isProxy(graph) || !Object.isFrozen(graph) || graph.length < 2)) {
        fail('ForeignInstalledSourceProducer');
      }
      if (state.prepared !== prepared || state.compilationFamily !== 'model' ||
          state.holder === undefined || state.inventoryHolder !== undefined || state.adopting ||
          state.preparing || state.modelGraph !== undefined && state.modelGraph !== graph &&
            (!multiple || state.modelGraph !== graph.at(-1))) {
        fail('ForeignInstalledSourceProducer');
      }
      const moon = state.context.runtime, contracts = originals.installation!.sequenceContractOriginal;
      if (contracts?.moon !== moon || moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) {
        fail('ForeignInstalledSourceProducer');
      }
      if (state.modelCompilation !== undefined) return state.modelCompilation;
      const compile = multiple ? moon.clientProgramPrepareRequestModelsCompilation
        : moon.clientProgramPrepareRequestModelCompilation;
      const issue = moon.clientProgramRequestProgramModuleIssueCode;
      if (typeof compile !== 'function' || typeof issue !== 'function') fail('NodeManagedRunRuntimeUnavailable');
      state.modelGraph = graph;
      return constructRequestDomain(state, () => {
        // The typed Request compiler owns this SAME raw TaskCompilation.
        // The Model module and Run issuer must consume it without compiling
        // the graph again or reinterpreting it as the Values/Tasks sum.
        state.modelCompilation = checkedRequestProgramPreparation(moon, Reflect.apply(compile, moon,
          [state.parent, producer!.receipt, graph, contracts.admission]), issue);
        if (state.modelCompilation === undefined) fail('NodeManagedRunCompilationUnavailable');
        current();
        if (producer!.finished || producer!.preparation !== state || state.prepared !== prepared ||
            state.modelGraph !== graph || moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) {
          fail('ForeignInstalledSourceProducer');
        }
        return state.modelCompilation;
      });
    },
    prepareContentGraph(prepared: object, request: object, constructOriginal: ConstructContentGraph): unknown {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined) return undefined;
      const effectful = state.compilationKind === 'effectful' && state.effectBorrowMethods !== undefined;
      if (state.prepared !== prepared || !effectful && !['content', 'model'].includes(state.compilationFamily!) ||
          state.holder === undefined || state.inventoryHolder !== undefined || state.adopting ||
          state.preparing || typeof constructOriginal !== 'function') fail('ForeignInstalledSourceProducer');
      const moon = state.context.runtime, contracts = originals.installation!.sequenceContractOriginal;
      const readOriginal = effectful ? state.effectBorrowMethods!.clientProgramEffectPreparationInputRead
        : moon.clientProgramPreparationBorrowRead;
      if (contracts?.moon !== moon || typeof readOriginal !== 'function' ||
          Reflect.apply(readOriginal, moon, [state.holder]) !== prepared) {
        fail('ForeignInstalledSourceProducer');
      }
      if (state.contentGraph !== undefined) return state.contentGraph;
      return constructRequestDomain(state, () => {
        // Retain before post-callback current can fail. This same Request's
        // original cleanup owns the native component and its partial peak.
        state.contentGraph = Reflect.apply(constructOriginal, undefined,
          [state.parent, producer!.receipt, contracts.admission, ...(effectful ? [true] : [])]);
        if (state.contentGraph === undefined) fail('NodeManagedRunCompilationUnavailable');
        current();
        if (producer!.finished || producer!.preparation !== state || state.prepared !== prepared ||
            Reflect.apply(readOriginal, moon, [state.holder]) !== prepared) fail('ForeignInstalledSourceProducer');
        return state.contentGraph;
      });
    },
    prepareContentCompilation(prepared: object, request: object, graph: unknown, compileOriginal: CompileContentGraph): unknown {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined) return undefined;
      if (state.prepared !== prepared || state.compilationFamily !== 'content' ||
          state.holder === undefined || state.inventoryHolder !== undefined || state.adopting ||
          state.preparing || typeof compileOriginal !== 'function' ||
          state.contentGraph !== undefined && state.contentGraph !== graph) fail('ForeignInstalledSourceProducer');
      const moon = state.context.runtime, contracts = originals.installation!.sequenceContractOriginal;
      if (contracts?.moon !== moon || moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) {
        fail('ForeignInstalledSourceProducer');
      }
      if (state.contentCompilation !== undefined) return state.contentCompilation;
      state.contentGraph = graph;
      return constructRequestDomain(state, () => {
        state.contentCompilation = Reflect.apply(compileOriginal, undefined,
          [state.parent, producer!.receipt, graph, contracts.admission]);
        if (state.contentCompilation === undefined) fail('NodeManagedRunCompilationUnavailable');
        current();
        if (producer!.finished || producer!.preparation !== state || state.prepared !== prepared ||
            moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) fail('ForeignInstalledSourceProducer');
        return state.contentCompilation;
      });
    },
    publicationPreparation(prepared: object) {
      const run = runFor(prepared), state = run.producer.preparation;
      if (state === undefined || state.prepared !== prepared ||
          state.holder === undefined || !state.adopting) {
        fail('ForeignInstalledSourceProducer');
      }
      if (run.value === undefined) fail('NodeManagedRunAdmissionUnavailable');
      return run.value;
    },
    originalExplanationPreparation(prepared: object) {
      const retained = runs.get(prepared);
      if (retained?.producer!.preparation?.originalExplanation === undefined) return undefined;
      const run = runFor(prepared), state = run.producer.preparation;
      if (state === undefined || state.prepared !== prepared || !state.adopting || run.value === undefined) {
        fail('ForeignInstalledSourceProducer');
      }
      return state.originalExplanation;
    },
    retireOriginalExplanation(prepared: object, original: unknown) {
      const run = runs.get(prepared);
      if (run === undefined || run.original !== original) fail('ForeignInstalledSourceProducer');
      // This runs before the caller retires the Core parent. Returning
      // normally permits that retirement, so a pending Journal loan must
      // stop the caller while the original capacity still backs it.
      if (!disposeOriginalExplanation(run.producer!.preparation)) {
        fail('InstalledExplanationAdmissionCleanupPending');
      }
    },
    reservePublication(prepared: object) {
      const run = publicationRunFor(prepared), state = run.producer.preparation;
      if (state === undefined || state.prepared !== prepared ||
          state.holder === undefined || !state.adopting) {
        fail('ForeignInstalledSourceProducer');
      }
      if (run.value === undefined) fail('NodeManagedRunAdmissionUnavailable');
      return checkedPreparation(state.context.runtime,
        state.context.runtime.clientProgramReservePublication(
          run.value, prepared));
    },
    compilationOriginal(prepared: object) {
      const run = runFor(prepared), state = run.producer.preparation;
      if (state === undefined || state.prepared !== prepared || state.holder === undefined || !state.adopting) {
        fail('ForeignInstalledSourceProducer');
      }
      if (run.value === undefined) fail('NodeManagedRunAdmissionUnavailable');
      const original = state.context.runtime.clientProgramInstalledManagedRunCompilationOriginal(run.value, prepared);
      if (original === undefined) fail('NodeManagedRunCompilationUnavailable');
      return original;
    },
    authoringContextOriginal(prepared: object, request: object) {
      current();
      const run = runs.get(prepared), producer = run?.producer ?? producerForRequest(request);
      const state = producer?.preparation;
      if (state === undefined || producer!.request !== request || state.prepared !== prepared ||
          state.compilationKind !== 'effect_free' || state.holder === undefined ||
          state.preparationFailed || state.authoringContextOriginal === undefined) {
        fail('ForeignInstalledSourceProducer');
      }
      const original = state.authoringContextOriginal;
      resourceRuntime.assertOrdinaryManagedRunCurrent(state.original!, producer!.receipt);
      // Current may synchronously retire this same Request. Retain no alias
      // unless its original state and borrow still own the exact proof.
      if (closed || closing || producer!.preparation !== state || producer!.request !== request ||
          state.prepared !== prepared || state.holder === undefined ||
          state.authoringContextOriginal !== original || state.preparationFailed ||
          (run === undefined ? producerForRequest(request) !== producer : runs.get(prepared) !== run)) {
        fail('ForeignInstalledSourceProducer');
      }
      return original;
    },
    adoptPreparation(prepared: object, request: object, identity: unknown, constructInvocation: InvocationConstructor | undefined) {
      current();
      const producer = producerForRequest(request);
      const state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined) return undefined;
      if (state.prepared !== prepared || state.holder === undefined || state.adopting ||
          state.compilationFamily !== 'pure' || state.acquisitionCount !== 0) fail('ForeignInstalledSourceProducer');
      const moon = state.context.runtime;
      const contracts = originals.installation!.sequenceContractOriginal;
      const module = moon.clientProgramPrepareRequestProgramModuleBody;
      const issue = moon.clientProgramRequestProgramModuleIssueCode;
      const adopt = moon.clientProgramAdoptRequestProgramPreparation;
      if (typeof adopt !== 'function' || state.requiresQueryTime &&
          (typeof module !== 'function' || typeof issue !== 'function')) {
        fail('NodeManagedRunRuntimeUnavailable');
      }
      const run: RegisteredRun = {prepared,request,producer: producer!,purpose:'source-compute',model:undefined,
        effectful:false,content:undefined,original:state.original,children:[],fileIdentity:undefined,value:undefined};
      state.adopting = true;
      try {
        registerRequestRun(run, () => {
          if (state.requiresQueryTime) {
            const invocation = originalTimedInvocation(state, producer!, prepared, constructInvocation, contracts);
            checkedRequestProgramPreparation(moon, Reflect.apply(module, moon,
              [state.parent, producer!.receipt, contracts!.admission,
                state.context.retainedRelationOutput, invocation, state.sourceFreeMaxWork]), issue);
            current();
            if (producer!.finished || producer!.preparation !== state || state.prepared !== prepared) {
              fail('ForeignInstalledSourceProducer');
            }
          }
          const explanation = state.originalExplanation;
          return explanation === undefined ? checked(Reflect.apply(adopt, moon, [state.parent, identity]))
            : checked(Reflect.apply(explanation.methods.adopt!, moon,
              [state.parent, identity, explanation.preparation]));
        });
        return run;
      } catch (cause) {
        reportCapacityRefusal(cause);
        state.adopting = false;
        if (state.requiresQueryTime) {
          state.preparationFailed = true; state.preparationFailure = cause;
        }
        throw cause;
      }
    },
    adoptCapturePreparation(prepared: object, request: object, identity: unknown, constructPlan: CapturePlanConstructor,
        constructInvocation: InvocationConstructor | undefined) {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined) return undefined; // Other purposes retain their existing owner.
      if (state.prepared !== prepared || state.holder === undefined || state.adopting ||
          state.compilationKind !== 'effect_free' || state.compilationFamily !== 'pure' || !(state.acquisitionCount! > 0) ||
          typeof constructPlan !== 'function') {
        fail('ForeignInstalledSourceProducer');
      }
      const moon = state.context.runtime;
      const contracts = originals.installation!.sequenceContractOriginal;
      const prepareModule = moon.clientProgramPrepareRequestCaptureModuleBody;
      const projectIssue = moon.clientProgramRequestProgramModuleIssueCode;
      const adopt = moon.clientProgramAdoptRequestCapturePreparation;
      if (typeof prepareModule !== 'function' || typeof projectIssue !== 'function' ||
          typeof adopt !== 'function') fail('NodeManagedRunRuntimeUnavailable');
      if (moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) {
        fail('ForeignInstalledSourceProducer');
      }
      const run: RegisteredRun = {prepared, request, producer: producer!, purpose: 'source-compute', model: undefined,
        effectful: false, content: undefined, original: state.original,
        children: [], fileIdentity: undefined, value: undefined};
      state.adopting = true;
      try {
        registerRequestRun(run, () => {
          // This private Host constructor uses its already retained Source
          // inventory, on the same input reservation. It is not a capacity or
          // authorization callback, and does not run for another purpose.
          const invocation = originalTimedInvocation(state, producer!, prepared, constructInvocation, contracts);
          const plan = state.requiresQueryTime ? constructPlan(invocation) : constructPlan();
          state.capturePlan = plan;
          current();
          if (producer!.finished || producer!.preparation !== state || state.prepared !== prepared) {
            fail('ForeignInstalledSourceProducer');
          }
          // The SAME Request already backs this Plan and retains its input borrow.
          // Construct/measure its original compilation before adoption; bare
          // completion would lose that artifact and force later re-preparation.
          checkedRequestProgramPreparation(moon,
            Reflect.apply(prepareModule, moon, state.requiresQueryTime
              ? [state.parent, producer!.receipt, plan, invocation] : [state.parent, producer!.receipt, plan]),
            projectIssue);
          return checked(Reflect.apply(adopt, moon, [state.parent, identity]));
        });
        // The actual Core Run now retains this same Plan. Do not keep a
        // second strong Plan root after its completed handoff.
        state.capturePlan = undefined;
        return run;
      } catch (cause) {
        state.adopting = false;
        state.preparationFailed = true; state.preparationFailure = cause;
        throw cause;
      }
    },
    prepareModelRun(prepared: object, request: object, identity: unknown,
        model: ModelAdoption, constructPlan: ModelPlanConstructor): RegisteredRun {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined || state.prepared !== prepared || state.compilationFamily !== 'model' ||
          state.adopting || state.preparing || typeof constructPlan !== 'function') {
        fail('ForeignInstalledSourceProducer');
      }
      const compilation = view.prepareModelCompilation(prepared, request, model.graph);
      constructRequestDomain(state, () => {
        // Retain before the adopter's first fallible current check. Partial
        // modules and this original Plan stay on the same Request for cleanup.
        state.modelPlan = Reflect.apply(constructPlan, undefined, [state.parent, producer!.receipt, compilation]);
      });
      return view.adoptModelPreparation(prepared, identity, state.modelPlan, model);
    },
    adoptModelPreparation(prepared: object, identity: unknown, modelPlan: unknown, model: ModelAdoption): RegisteredRun {
      current();
      const request = callbacks.request!(originals, prepared);
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (model === null || typeof model !== 'object' || types.isProxy(model) ||
          state === undefined || state.prepared !== prepared || state.compilationFamily !== 'model' ||
          state.modelCompilation === undefined || state.modelGraph !== model?.graph ||
          state.holder === undefined || state.inventoryHolder !== undefined || state.adopting ||
          state.preparing) {
        fail('ForeignInstalledSourceProducer');
      }
      // This is the existing physical caller's record, retained before entry.
      // Its Scope must survive a later completion/adoption failure.
      const scopeField = Object.getOwnPropertyDescriptor(model, 'scope');
      if (scopeField === undefined || !Object.hasOwn(scopeField, 'value') ||
          scopeField.value !== undefined || scopeField.writable !== true) fail('ForeignInstalledSourceProducer');
      const members = Object.getOwnPropertyDescriptor(model, 'components')?.value as readonly ModelAdoptionMember[] | undefined;
      const multiple = members !== undefined;
      if (multiple && (!Array.isArray(members) || !Object.isFrozen(members) || members.length < 2 ||
          !Array.isArray(model.graph) || model.graph.length !== members.length ||
          members.some((member, index) => member === null || typeof member !== 'object' || types.isProxy(member) ||
            member.group !== model || member.graph !== (model.graph as readonly unknown[])[index] || member.scope !== undefined ||
            Object.getOwnPropertyDescriptor(member, 'scope')?.writable !== true) ||
          Object.getOwnPropertyDescriptor(model, 'scopes')?.value !== undefined ||
          Object.getOwnPropertyDescriptor(model, 'scopes')?.writable !== true)) {
        fail('ForeignInstalledSourceProducer');
      }
      const moon = state.context.runtime;
      const plannedQuantities = multiple && members.every(member => member.originalReadInstallation !== undefined);
      const quantityLimits = plannedQuantities ? undefined : model.selection?.quantityCapacity?.limits;
      if (multiple && !plannedQuantities && quantityLimits === undefined && members.some(member =>
          member.selection?.quantityCapacity !== undefined)) fail('InstalledModelQuantityCapacityUnavailable');
      const scope = plannedQuantities ? moon.clientProgramPrepareRequestModelsReadScopesWithPlannedQuantities
        : multiple
          ? quantityLimits === undefined ? moon.clientProgramPrepareRequestModelsReadScopes
            : moon.clientProgramPrepareRequestModelsReadScopesWithQuantities
          : quantityLimits === undefined ? moon.clientProgramPrepareRequestModelReadScope
            : moon.clientProgramPrepareRequestModelReadScopeWithQuantities;
      const complete = moon.clientProgramCompleteRequestModelPreparation;
      const adopt = multiple ? moon.clientProgramAdoptRequestModelsPreparation
        : moon.clientProgramAdoptRequestModelPreparation;
      if (![scope, complete, adopt].every(method => typeof method === 'function')) {
        fail('NodeManagedRunRuntimeUnavailable');
      }
      if (moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) fail('ForeignInstalledSourceProducer');
      state.modelPlan = modelPlan;
      const run: RegisteredRun = {prepared, request, producer: producer!, purpose: 'local-mock-model', model,
        effectful: false, content: undefined, original: state.original,
        children: [], fileIdentity: undefined, value: undefined};
      state.adopting = true;
      try {
        registerRequestRun(run, () => {
          const issued = checked(Reflect.apply(scope!, moon, [state.parent, producer!.receipt, modelPlan,
            ...(quantityLimits === undefined ? [] : [quantityLimits.tokens,
              quantityLimits.costUnits, quantityLimits.durationMs])]));
          // Retain the WHOLE native return before validation/current/complete.
          // Partial adoption must not strand a later original Scope.
          if (multiple) {
            model.scopes = issued;
            if (!Array.isArray(issued) || issued.length !== members.length) fail('NodeManagedRunAdmissionUnavailable');
            // Keep the native return itself; callbacks cannot replace an
            // original Scope slot before partial-constructor retirement.
            Object.freeze(issued);
            for (let index = 0; index < members.length; index++) members[index].scope = issued[index];
            model.scope = issued[0];
          } else model.scope = issued;
          if (model.scope === undefined || multiple && members.some(member => member.scope === undefined)) {
            fail('NodeManagedRunAdmissionUnavailable');
          }
          checked(Reflect.apply(complete!, moon, [state.parent, producer!.receipt, modelPlan]));
          return checked(Reflect.apply(adopt!, moon, [state.parent, identity, multiple ? model.scopes : model.scope]));
        });
        state.modelCompilation = state.modelGraph = state.modelPlan = state.modelProviderBinding = state.contentGraph = undefined;
        return run;
      } catch (cause) {
        state.adopting = false;
        state.preparationFailed = true; state.preparationFailure = cause;
        throw cause;
      }
    },
    modelSourceCoordinates(prepared: object, request: object): readonly ModelCoordinate[] | undefined {
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state?.recovery !== undefined) {
        const recovery = state.recovery;
        if (state.prepared !== prepared || recovery.restored?.prepared !== prepared || state.preparing || state.adopting) fail('ForeignInstalledSourceProducer');
        if (state.modelSourceCoordinates !== undefined) return state.modelSourceCoordinates;
        reserveModelRecovery(producer!, state, 1, () => recovery.original!.materialsWire, 1);
        return constructRequestDomain(state, () => {
          const control = recovery.model?.control ?? runtimeCore(state.context.runtime).publicationControl;
          const coordinates = control.checkedClientRequestModelRecoverySourceCoordinates(
            state.parent, producer!.receipt, recovery.request, recovery.definition, prepared);
          if (!Array.isArray(coordinates) || coordinates.some(value => !Array.isArray(value) || value.length !== 3 ||
              value.some(coordinate => !Number.isSafeInteger(coordinate) || coordinate < 0))) fail('InvalidHostRuntimeResult');
          for (const coordinate of coordinates) Object.freeze(coordinate);
          state.modelSourceCoordinates = Object.freeze(coordinates);
          current(); recovery.assertCurrent();
          if (producer!.finished || producer!.preparation !== state || state.recovery !== recovery) fail('ForeignInstalledSourceProducer');
          return state.modelSourceCoordinates;
        });
      }
      if (state === undefined || state.compilationFamily !== 'model') return undefined;
      current();
      if (state.prepared !== prepared || state.holder === undefined || state.parent === undefined || state.preparing ||
          state.inventoryHolder !== undefined) fail('ForeignInstalledSourceProducer');
      if (state.modelSourceCoordinates !== undefined) return state.modelSourceCoordinates;
      if (state.adopting) fail('ForeignInstalledSourceProducer');
      const moon = state.context.runtime, parent = state.parent, holder = state.holder;
      const select = Object.getOwnPropertyDescriptor(moon, 'clientProgramRequestModelDirectSourceCoordinates')?.value;
      if (typeof select !== 'function') fail('NodeManagedRunRuntimeUnavailable');
      if (moon.clientProgramPreparationBorrowRead(holder) !== prepared) fail('ForeignInstalledSourceProducer');
      const coordinates = checked(Reflect.apply(select, moon, [parent, producer!.receipt]));
      // This immutable projection supplies no authority. Keep the same exact
      // checked Stage/input/task DATA through submission after Plan adoption.
      if (!Array.isArray(coordinates) || coordinates.some(value => !Array.isArray(value) || value.length !== 3 ||
          value.some(coordinate => !Number.isSafeInteger(coordinate) || coordinate < 0))) fail('InvalidHostRuntimeResult');
      for (const value of coordinates) Object.freeze(value);
      state.modelSourceCoordinates = Object.freeze(coordinates);
      current();
      if (producer!.preparation !== state || state.prepared !== prepared || state.parent !== parent || state.holder !== holder ||
          state.context.runtime !== moon || moon.clientProgramPreparationBorrowRead(holder) !== prepared) {
        fail('ForeignInstalledSourceProducer');
      }
      return state.modelSourceCoordinates;
    },
    selectDomainSourceInput(prepared: object, request: object, identity: unknown, stage: number, sourceIndex: number): unknown {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined) return undefined; // A separately owned legacy purpose.
      if (state.recovery !== undefined) {
        const recovery = state.recovery, restored = recovery.restored, parent = state.parent;
        if (state.compilationFamily !== 'model-recovery' || state.preparing || state.adopting ||
            state.prepared !== prepared || restored?.prepared !== prepared || parent === undefined ||
            identity !== recovery.request || restored.runDefinition !== recovery.definition ||
            typeof recovery.original?.materialsWire !== 'string' ||
            !Number.isSafeInteger(stage) || stage < 0 ||
            !Number.isSafeInteger(sourceIndex) || sourceIndex < 0) fail('ForeignInstalledSourceProducer');
        // The original saved material bounds this derived metadata constructor
        // too. This consumes no Source bytes and issues no Model read/Run.
        reserveModelRecovery(producer!, state, 1, () => recovery.original!.materialsWire, 1);
        const moon = state.context.runtime;
        return constructRequestDomain(state, () => {
          recovery.assertCurrent();
          const selected = checked(moon.clientProgramSelectInstalledSourceInput(prepared, identity, stage, sourceIndex));
          current();
          if (producer!.finished || producer!.preparation !== state || state.parent !== parent ||
              state.prepared !== prepared || state.recovery !== recovery || recovery.restored !== restored ||
              recovery.request !== identity || restored.runDefinition !== recovery.definition) fail('ForeignInstalledSourceProducer');
          recovery.assertCurrent();
          if (producer!.finished || producer!.preparation !== state || state.recovery !== recovery ||
              recovery.restored !== restored) fail('ForeignInstalledSourceProducer');
          return selected;
        });
      }
      if (state.prepared !== prepared || state.compilationKind !== 'effect_free') fail('ForeignInstalledSourceProducer');
      if (state.compilationFamily === 'pure') return undefined;
      if (!['model', 'content'].includes(state.compilationFamily!) || state.holder === undefined ||
          state.parent === undefined || state.inventoryHolder !== undefined || state.preparing ||
          !Number.isSafeInteger(stage) || stage < 0 || !Number.isSafeInteger(sourceIndex) || sourceIndex < 0) {
        fail('ForeignInstalledSourceProducer');
      }
      const moon = state.context.runtime, holder = state.holder, parent = state.parent;
      // Submission revisits the SAME Prepared after Plan adoption. The
      // original live Run bag, not another preparation, supplies that custody.
      const adopted = state.adopting === true;
      const run = adopted ? runs.get(prepared) : undefined;
      if (adopted && (run === undefined || run.closed || run.producer !== producer ||
          run.prepared !== prepared || run.request !== request || run.original !== state.original ||
          run.value === undefined)) fail('ForeignInstalledSourceProducer');
      const value = run?.value;
      const select = Object.getOwnPropertyDescriptor(moon, 'clientProgramSelectInstalledSourceInput')?.value;
      if (typeof select !== 'function') fail('NodeManagedRunRuntimeUnavailable');
      if (moon.clientProgramPreparationBorrowRead(holder) !== prepared) fail('ForeignInstalledSourceProducer');
      // The actual Model/Content Plan borrow already owns this Request's
      // variable construction input. Select only its nominal Source original;
      // the backed domain constructor creates the complete Query exactly once.
      return constructRequestDomain(state, () => {
        const selected = checked(Reflect.apply(select, moon, [prepared, identity, stage, sourceIndex]));
        current();
        if (producer!.finished || producer!.preparation !== state || state.prepared !== prepared ||
            state.parent !== parent || state.holder !== holder || state.context.runtime !== moon ||
            (state.adopting === true) !== adopted ||
            adopted && (runs.get(prepared) !== run || run!.closed || run!.value !== value ||
              run!.request !== request || run!.producer !== producer || run!.original !== state.original) ||
            moon.clientProgramPreparationBorrowRead(holder) !== prepared) fail('ForeignInstalledSourceProducer');
        return selected;
      });
    },
    retainContentPreparation(prepared: object, request: object, contentPreparation: RetainedContentPreparation) {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state === undefined || state.prepared !== prepared || !['model', 'content'].includes(state.compilationFamily!) ||
          state.holder === undefined || state.adopting || state.preparing ||
          contentPreparation?.prepared !== prepared || contentPreparation.retired ||
          typeof Object.getOwnPropertyDescriptor(contentPreparation, 'releaseAliases')?.value !== 'function' ||
          state.contentPreparation !== undefined && state.contentPreparation !== contentPreparation ||
          state.context.runtime.clientProgramPreparationBorrowRead(state.holder) !== prepared) {
        fail('ForeignInstalledSourceProducer');
      }
      // No fallible callback follows taking this original record. Failed
      // construction keeps it until the same Request's abort fence below.
      state.contentPreparation = contentPreparation;
      contentPreparation.inputHolder = state.holder;
    },
    prepareKeyedContentRun(prepared: object, request: object, identity: unknown, graph: unknown,
        constructPlan: PlanConstructor, compileOriginal: KeyedContentCompiler,
        contentPreparation: RetainedContentPreparation): RegisteredRun {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined || state.prepared !== prepared || state.compilationFamily !== 'content' ||
          state.holder === undefined || state.inventoryHolder !== undefined || state.adopting ||
          state.preparing || state.contentGraph !== undefined && state.contentGraph !== graph ||
          state.contentPreparation !== contentPreparation ||
          typeof constructPlan !== 'function' || typeof compileOriginal !== 'function') {
        fail('ForeignInstalledSourceProducer');
      }
      const moon = state.context.runtime;
      if (moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) fail('ForeignInstalledSourceProducer');
      state.contentGraph = graph;
      constructRequestDomain(state, () => {
        // The same Request owns the original selected keyed Plan BEFORE its
        // compiler consumes that Plan, graph and immutable contract inputs.
        state.contentPlan = Reflect.apply(constructPlan, undefined, [state.parent, producer!.receipt]);
        if (state.contentPlan === undefined) fail('InstalledContentRunPreparationUnavailable');
        state.contentCompilation = Reflect.apply(compileOriginal, undefined,
          [state.parent, producer!.receipt, state.contentPlan, graph]);
        if (state.contentCompilation === undefined) fail('NodeManagedRunCompilationUnavailable');
        current();
        if (producer!.finished || producer!.preparation !== state || state.prepared !== prepared ||
            moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) fail('ForeignInstalledSourceProducer');
      });
      return view.adoptContentPreparation(prepared, identity, state.contentPlan);
    },
    prepareSerializationOutputDemand<Value>(prepared: object, request: object,
        construct: (parent: unknown, receipt: object, content: unknown) => Value): Value {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined || state.prepared !== prepared ||
          !['content', 'model'].includes(state.compilationFamily!) || state.holder === undefined ||
          state.preparing || state.adopting || typeof construct !== 'function') fail('ForeignInstalledSourceProducer');
      const original = state.contentPreparation, holder = state.holder, moon = state.context.runtime;
      const content = original === undefined ? undefined
        : Object.getOwnPropertyDescriptor(original, 'contentControl')?.value;
      if (original?.prepared !== prepared || original.retired || original.inputHolder !== holder ||
          content === undefined || moon.clientProgramPreparationBorrowRead(holder) !== prepared) {
        fail('ForeignInstalledSourceProducer');
      }
      return constructRequestDomain(state, () => {
        // The retained Content record owns this facade and its paired
        // publication control. A fresh facade cannot consume its workspace.
        const selected = construct(state.parent, producer!.receipt, content);
        current();
        if (producerForRequest(request) !== producer || producer!.preparation !== state ||
            state.prepared !== prepared || state.holder !== holder || state.context.runtime !== moon ||
            state.contentPreparation !== original || original.prepared !== prepared || original.retired ||
            original.inputHolder !== holder || Object.getOwnPropertyDescriptor(original, 'contentControl')?.value !== content ||
            moon.clientProgramPreparationBorrowRead(holder) !== prepared) {
          fail('ForeignInstalledSourceProducer');
        }
        return selected;
      });
    },
    prepareSerializationRun(prepared: object, request: object, identity: unknown,
        constructPlan: PlanConstructor, contentPreparation: RetainedContentPreparation): RegisteredRun {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined || state.prepared !== prepared || state.compilationFamily !== 'content' ||
          state.contentCompilation === undefined || state.holder === undefined || state.adopting ||
          state.preparing || state.contentPreparation !== contentPreparation || typeof constructPlan !== 'function') fail('ForeignInstalledSourceProducer');
      constructRequestDomain(state, () => {
        state.contentPlan = Reflect.apply(constructPlan, undefined, [state.parent, producer!.receipt]);
      });
      return view.adoptContentPreparation(prepared, identity, state.contentPlan, true);
    },
    adoptContentPreparation(prepared: object, identity: unknown, contentPlan: unknown, serialization = false): RegisteredRun {
      current();
      const request = callbacks.request!(originals, prepared);
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined || state.prepared !== prepared || state.compilationFamily !== 'content' ||
          state.holder === undefined || state.inventoryHolder !== undefined || state.adopting ||
          state.preparing) fail('ForeignInstalledSourceProducer');
      const moon = state.context.runtime;
      const complete = serialization ? moon.clientProgramCompleteRequestSerializationPreparation
        : moon.clientProgramCompleteRequestContentPreparation;
      const adopt = moon.clientProgramAdoptRequestContentPreparation;
      if (typeof complete !== 'function' || typeof adopt !== 'function') fail('NodeManagedRunRuntimeUnavailable');
      if (moon.clientProgramPreparationBorrowRead(state.holder) !== prepared) fail('ForeignInstalledSourceProducer');
      state.contentPlan = contentPlan;
      // Child-count DATA comes from this same typed selected Plan. It neither
      // retains another Resource original nor replaces the adopted Core Ledger.
      const run: RegisteredRun = {prepared, request, producer: producer!, purpose: 'local-content', model: undefined,
        effectful: false, content: contentPlan, original: state.original, required: undefined,
        children: [], fileIdentity: undefined, value: undefined};
      state.adopting = true;
      try {
        registerRequestRun(run, () => {
          run.required = serialization ? undefined : callbacks.contentRequirements!(originals, prepared, contentPlan);
          checked(Reflect.apply(complete, moon, serialization
            ? [state.parent, producer!.receipt, contentPlan] : [state.parent, producer!.receipt, identity, contentPlan]));
          return checked(Reflect.apply(adopt, moon, [state.parent, identity]));
        });
        state.contentPlan = state.contentCompilation = state.contentGraph = undefined;
        return run;
      } catch (cause) {
        state.adopting = false;
        state.preparationFailed = true; state.preparationFailure = cause;
        throw cause;
      }
    },
    adoptEffectPreparation(prepared: object, request: object, identity: unknown, operationPlan: object,
        keyedPreparation?: KeyedEffectPreparation): RegisteredRun {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined || state.prepared !== prepared || state.holder === undefined ||
          state.compilationKind !== 'effectful' || state.effectBorrowMethods === undefined ||
          state.adopting || runs.has(prepared) || pendingRunRegistrations.has(prepared) ||
          producer!.liveRuns === Number.MAX_SAFE_INTEGER ||
          liveRuns.size + pendingRunRegistrations.size >= 4096 || operationPlan === null || typeof operationPlan !== 'object') {
        fail('ForeignInstalledSourceProducer');
      }
      if (state.effectMaterials !== undefined && (state.effectMaterials.request !== request ||
          state.effectMaterials.identity !== identity)) fail('ForeignInstalledSourceProducer');
      const moon = state.context.runtime, methods = state.effectBorrowMethods;
      if (methods.clientProgramEffectPreparationInputRead(state.holder) !== prepared) {
        fail('ForeignInstalledSourceProducer');
      }
      // Retain the actual selected Plan before either fallible Core operation.
      // Failed completion stays on this same Request for original cleanup.
      state.effectPlan = operationPlan;
      state.adopting = true;
      try {
        if (keyedPreparation !== undefined) {
          if (keyedPreparation.graph !== state.effectKeyedPlan ||
              typeof state.effectBorrowMethods.clientProgramPrepareRequestEffectKeyedOriginal !== 'function') {
            fail('ForeignInstalledSourceProducer');
          }
          // Bind before completion/adoption can discard an unused census.
          // The control unwraps only its own actual compiled/Definition pair.
          runtimeCore(moon).publicationControl.bindCheckedClientRequestEffectKeyedOriginal(
            state.parent, producer!.receipt, operationPlan, keyedPreparation.compilation,
            keyedPreparation.compiled, keyedPreparation.runDefinition,
            keyedPreparation.graph, keyedPreparation.acquisition,
            methods.clientProgramPrepareRequestEffectKeyedOriginal!);
        }
        checked(methods.clientProgramCompleteRequestEffectPreparation!(state.parent, producer!.receipt, operationPlan));
        const value = checked(methods.clientProgramAdoptRequestEffectPreparation!(state.parent, identity));
        const run: RegisteredRun = {prepared, request, producer: producer!, purpose: 'source-compute', model: undefined,
          effectful: true, content: undefined, operationPlan, original: state.original,
          ...(keyedPreparation === undefined ? {} : {keyedPreparation}),
          children: [], fileIdentity: undefined, value};
        producer!.liveRuns++;
        runs.set(prepared, run); liveRuns.add(run);
        state.modelGraph = undefined;
        return run;
      } catch (cause) {
        state.adopting = false;
        state.preparationFailed = true; state.preparationFailure = cause;
        throw cause;
      }
    },
    adoptEffectModelPreparation(prepared: object, request: object, identity: unknown, operationPlan: object,
        retainedRun: InstalledEffectModelRun): RegisteredRun {
      current();
      const producer = producerForRequest(request), state = producer?.preparation;
      if (state?.preparationFailed) throw state.preparationFailure;
      if (state === undefined || state.prepared !== prepared || state.holder === undefined ||
          state.compilationKind !== 'effectful' || state.effectBorrowMethods === undefined ||
          state.adopting || runs.has(prepared) || pendingRunRegistrations.has(prepared) ||
          producer!.liveRuns === Number.MAX_SAFE_INTEGER ||
          liveRuns.size + pendingRunRegistrations.size >= 4096 || operationPlan === null || typeof operationPlan !== 'object' ||
          retainedRun === null || typeof retainedRun !== 'object' || types.isProxy(retainedRun)) {
        fail('ForeignInstalledSourceProducer');
      }
      const fields = Object.getOwnPropertyDescriptors(retainedRun);
      for (const [name, original] of ([['manager', view], ['runtime', state.context.runtime],
        ['preparationKind', 'effect-plan'], ['prepared', prepared], ['request', identity],
        ['requestInput', request], ['operationPlan', operationPlan], ['original', undefined],
        ['modelScope', undefined], ['value', undefined], ['closed', false]] as const)) {
        if (!Object.hasOwn(fields[name] ?? {}, 'value') ||
            fields[name]?.value !== original) fail('ForeignInstalledSourceProducer');
      }
      if (state.effectMaterials !== undefined && (state.effectMaterials.request !== request ||
          state.effectMaterials.identity !== identity)) fail('ForeignInstalledSourceProducer');
      const methods = state.effectBorrowMethods;
      const quantityLimits = retainedRun.modelSelection?.quantityCapacity?.limits;
      const plural = Array.isArray(retainedRun.modelMembers);
      if (plural && (!Object.isFrozen(retainedRun.modelMembers) || retainedRun.modelMembers!.length < 2 ||
          !Array.isArray(retainedRun.modelSelection?.components) ||
          retainedRun.modelMembers!.length !== retainedRun.modelSelection.components.length ||
          retainedRun.modelMembers!.some((member, index) => member.model !== retainedRun.model!.components![index] ||
            member.modelSelection !== retainedRun.modelSelection!.components![index] || member.modelScope !== undefined))) {
        fail('ForeignInstalledSourceProducer');
      }
      if (plural && quantityLimits === undefined && retainedRun.modelSelection!.components!.some(
          member => member.quantityCapacity !== undefined)) fail('InstalledModelQuantityCapacityUnavailable');
      const prepareScope = plural ? quantityLimits === undefined ? methods.clientProgramPrepareRequestEffectModelsReadScopes
        : methods.clientProgramPrepareRequestEffectModelsReadScopesWithQuantities
        : quantityLimits === undefined ? methods.clientProgramPrepareRequestEffectModelReadScope
          : methods.clientProgramPrepareRequestEffectModelReadScopeWithQuantities;
      const adoptModel = plural ? methods.clientProgramAdoptRequestEffectModelsPreparation
        : methods.clientProgramAdoptRequestEffectModelPreparation;
      if (typeof prepareScope !== 'function' || typeof adoptModel !== 'function') {
        fail('NodeManagedRunRuntimeUnavailable');
      }
      if (methods.clientProgramEffectPreparationInputRead(state.holder) !== prepared) {
        fail('ForeignInstalledSourceProducer');
      }
      // The existing outer Run already owns this construction. Store its SAME
      // Scope before completion/adoption can fail; no cleanup callback, new
      // manager admission or second Scope owner is introduced.
      retainedRun.original = state.original;
      state.effectPlan = operationPlan;
      state.adopting = true;
      try {
        const issued = checked(prepareScope(state.parent, producer!.receipt, operationPlan,
          ...(quantityLimits === undefined ? [] : [quantityLimits.tokens,
            quantityLimits.costUnits, quantityLimits.durationMs])));
        // Retain the complete native return before current/adoption can fail.
        if (plural) {
          retainedRun.modelScopes = issued as readonly unknown[];
          if (!Array.isArray(issued) || issued.length !== retainedRun.modelMembers!.length) fail('NodeManagedRunAdmissionUnavailable');
          Object.freeze(issued);
          for (let index = 0; index < issued.length; index++) retainedRun.modelMembers![index].modelScope = issued[index];
        } else retainedRun.modelScope = issued;
        checked(methods.clientProgramCompleteRequestEffectPreparation!(state.parent, producer!.receipt, operationPlan));
        const value = checked(adoptModel(
          state.parent, identity, plural ? retainedRun.modelScopes : retainedRun.modelScope));
        const run: RegisteredRun = {prepared, request, producer: producer!, purpose: 'source-compute', model: retainedRun,
          effectful: true, content: undefined, operationPlan, original: state.original,
          children: [], fileIdentity: undefined, value};
        producer!.liveRuns++;
        runs.set(prepared, run); liveRuns.add(run);
        state.modelGraph = undefined;
        return run;
      } catch (cause) {
        state.adopting = false;
        state.preparationFailed = true; state.preparationFailure = cause;
        throw cause;
      }
    },
    severPreparation(prepared: object, original: unknown) {
      const run = runs.get(prepared), producer = run?.producer, state = producer?.preparation;
      if (run === undefined || run.original !== original || state === undefined || !state.adopting) {
        fail('ForeignInstalledSourceProducer');
      }
      if (state.holder === undefined) {
        // A valid return consumes the token before a possible settlement
        // failure. These fields are cut only after the exact Core sever
        // witness; retry continues the retained Run cleanup, never returns a
        // consumed holder or reconstructs a Prepared identity.
        if (state.prepared === undefined && run.prepared === undefined && run.request === undefined &&
            producer!.body === undefined && producer!.request === undefined) return;
        fail('ForeignInstalledSourceProducer');
      }
      const moon = state.context.runtime;
      const severed = state.effectBorrowMethods === undefined
        ? moon.clientProgramPreparationBorrowRead(state.holder) === prepared &&
          moon.clientProgramPreparationBorrowRetirementStarted(state.holder) === true
        : state.effectBorrowMethods.clientProgramEffectPreparationInputRead(state.holder) === prepared &&
          state.effectBorrowMethods.clientProgramEffectPreparationInputRetirementStarted(state.holder) === true;
      if (state.prepared !== prepared || severed !== true) {
        fail('ForeignInstalledSourceProducer');
      }
      if (state.contentPreparation !== undefined) {
        if (state.contentPreparation.retired !== true) fail('InstalledContentRunCleanupPending');
        state.contentPreparation = undefined;
      }
      // Original membership/currentness depends only on this receipt/state,
      // not the heavy request after retirement has fenced new operations.
      producer!.body = producer!.request = producer!.snapshotPublication = undefined;
      run.prepared = run.request = undefined;
      state.prepared = state.snapshot = state.snapshotDocument = state.parametersCursor = undefined;
      state.capturePlan = state.effectPlan = run.operationPlan = run.content = undefined;
      state.effectMaterials = undefined;
      state.authoringContextOriginal = undefined;
      state.modelProviderBinding = state.modelSourceCoordinates = undefined;
      state.preparationFailure = state.originalCheckResult = state.projectOriginalCheck = undefined;
      state.preparationFailed = false;
      const holder = state.holder;state.holder = undefined;
      checked(state.effectBorrowMethods === undefined
        ? state.context.runtime.clientProgramPreparationBorrowReturn(holder)
        : state.effectBorrowMethods.clientProgramEffectPreparationInputReturn(holder));
    },
    retireSeveredPreparation(original: object) {
      let run;
      for (const candidate of liveRuns) if (candidate.original === original) {run=candidate;break;}
      if (run === undefined || run.prepared !== undefined || run.request !== undefined ||
          !resourceRuntime.ordinaryManagedRunStatus(original).stopped) fail('InstalledSourceRunCleanupPending');
      const producer=run.producer!,state=producer.preparation;
      if (state===undefined || state.holder!==undefined || state.prepared!==undefined || producer.liveRuns<1) {
        fail('ForeignInstalledSourceProducer');
      }
      if (!disposeOriginalExplanation(state)) fail('InstalledExplanationAdmissionCleanupPending');
      liveRuns.delete(run);producer.liveRuns--;
      producer.preparation=undefined;
      state.parent=state.admission=state.original=(state as {context: Context | undefined}).context=undefined;
      state.compilationKind=state.preparationFailure=state.originalCheckResult=state.projectOriginalCheck=undefined;state.preparationFailed=false;
      state.compilationFamily=undefined;
      state.policyVerifier=state.policySignal=undefined;state.policyVerifierSelected=false;
      run.value=run.producer=undefined;
      releaseFinishedProducer(producer);
    },
    borrowPreparation(prepared: object, request: object) {
      current();
      const producer = producerForRequest(request);
      const state = producer?.preparation;
      if (state === undefined) return undefined;
      if (state.prepared !== prepared || state.holder === undefined || state.adopting) {
        fail('ForeignInstalledSourceProducer');
      }
      return checked(state.effectBorrowMethods === undefined
        ? state.context.runtime.clientProgramPreparationBorrowSibling(state.holder)
        : state.effectBorrowMethods.clientProgramEffectPreparationInputSibling!(state.holder));
    },
    intentCid(receipt: object, body: RequestSnapshot) {
      current(); const producer = producerFor(receipt);
      if (producer.body !== body || producer.finished) fail('ForeignInstalledSourceProducer');
      const state = producer.preparation;
      if (state?.parent !== undefined) {
        // Fixed shallow DATA projection of the SAME detached snapshot. No
        // second serializer, native hash operation or no-owner fallback.
        const value = {kind: body.kind, input: body.input, parameters: body.parameters,
          ...(Object.hasOwn(body, 'stopBefore') ? {stopBefore: body.stopBefore} : {}),
          ...(Object.hasOwn(body, 'readOnly') ? {readOnly: body.readOnly} : {}),
      ...(Object.hasOwn(body, 'executionProfile') ? {executionProfile: body.executionProfile} : {})};
        const moon = state.context.runtime;
        const cid = checked(moon.clientProgramPrepareRequestSubmittedIntent(state.parent, receipt, value)) as string;
        // The original native/canonical/writer stack has returned. Only now
        // may the same owner reduce its temporary constructor peak.
        checked(moon.clientProgramFinishRequestSubmittedIntent(state.parent, receipt));
        return cid;
      }
      return callbacks.intent!(originals, view, body);
    },
    finishSourceProducer(receipt: object, terminal: 'failed' | 'returned') {
      const producer = producerFor(receipt);
      if (terminal !== 'failed' && terminal !== 'returned') fail('ForeignInstalledSourceProducer');
      producer.finished = true; producer.body = undefined;
      if (producer.liveRuns === 0 && producer.preparation !== undefined) {
        if (producer.preparation.recovery?.childrenPending() === true) fail('InstalledSourceRunCleanupPending');
        producer.request = producer.snapshotPublication = undefined;
        cleanupOriginalRequestInput(producer.preparation, retireInitialPreparation);
        producer.preparation = undefined;
      }
      producers.delete(producer);
      releaseFinishedProducer(producer);
    },
    beforeResultRead() {current();}, assertResultReadCurrent: current,
    // Existing original cleanup only; neither a caller terminal flag nor
    // request completion can acknowledge this Run or its physical children.
    retireRun(prepared: object, original: object | undefined) {
      if (retiredRuns.has(prepared)) {
        if (retiredRuns.get(prepared) !== original) fail('ForeignInstalledSourceProducer');
        return;
      }
      const run = runs.get(prepared);
      if (run === undefined || original === undefined || run.original !== original) {
        fail('ForeignInstalledSourceProducer');
      }
      const observed = resourceRuntime.ordinaryManagedRunStatus(original);
      if (!observed.stopped || run.children.some(child => child.flight !== undefined || !child.closed)) {
        fail('InstalledSourceRunCleanupPending');
      }
      if (!disposeOriginalExplanation(run.producer!.preparation)) fail('InstalledExplanationAdmissionCleanupPending');
      const producer = run.producer!;
      if (producer.liveRuns < 1) fail('ForeignInstalledSourceProducer');
      runs.delete(prepared);
      liveRuns.delete(run);
      retiredRuns.set(prepared, original);
      producer.liveRuns--;
      run.prepared = run.request = run.producer = undefined;
      run.model = run.content = run.operationPlan = run.required = run.fileIdentity = undefined;
      run.children = [];
      releaseFinishedProducer(producer);
    },
    // Project ordinary Sources adopt their existing Request. Their view no
    // longer exports the detached Source-compute Root preparation entrance.
    ...(project ? {} : {prepareRun(prepared: object) {
      return prepareRun(prepared, 'source-compute', undefined);
    }}),
    prepareRead(prepared: object, declaration: object, originalRun: unknown,
        occurrence?: SourceOccurrence | null, requestIdentity?: object) {
      const run = runFor(prepared);
      const declared = bundle?.sources.findIndex(source => source.declaration === declaration);
      // A declaration is an installed factory, not an acquisition occurrence.
      // Several published names can borrow it in the same checked Run. Keep
      // each caller's original slot instead of coalescing its physical child.
      const index = project || occurrence !== undefined ? occurrence?.task : declared;
      const expectedRun = run.producer.preparation === undefined ? run.original : run.value;
      if (declared === undefined || declared < 0 || run.prepared !== prepared ||
          expectedRun === undefined || expectedRun !== originalRun ||
          occurrence !== undefined && (occurrence === null || !(['stage', 'input', 'task'] as const).every(name =>
            Number.isSafeInteger(occurrence[name]) && occurrence[name] >= 0)) ||
          project && (!Number.isSafeInteger(index) || index! < 0 ||
            !Number.isSafeInteger(occurrence!.computeTask ?? index) ||
            (occurrence!.computeTask ?? index!) < 0) ||
          run.children.some(child => child.index === index)) fail('InstalledSourcePreparationMismatch');
      if (project) {
        const state = run.producer.preparation;
        const moon = state?.context.runtime;
        const select = run.effectful ? moon?.clientProgramInstalledEffectManagedSourceOccurrence
          : moon?.clientProgramInstalledManagedSourceOccurrence;
        if (requestIdentity === undefined || typeof select !== 'function') fail('InstalledSourcePreparationMismatch');
        // The retained Plan bounds this original Source slot and binds its
        // authored stage/input and actual Compute task to the SAME Request.
        // Source slots need not equal stages or Compute tasks.
        const selected = checked(Reflect.apply(select, moon,
          [expectedRun, prepared, requestIdentity, index]));
        if (runtimeOptionalField(selected, 0) !== occurrence!.stage ||
            runtimeOptionalField(selected, 1) !== occurrence!.input ||
            runtimeOptionalField(selected, 2) !== (occurrence!.computeTask ?? index) ||
            runs.get(prepared) !== run || run.producer.preparation !== state ||
            run.value !== expectedRun || run.children.some(child => child.index === index)) {
          fail('InstalledSourcePreparationMismatch');
        }
      }
      const child: SourceReaderChild & {index?: number} = {index, attempted: false, closed: false, bytes: undefined, flight: undefined,
        closing: false, cleanup: undefined, cleanupStatus: undefined, cleanupRetry: undefined,
        reader: undefined, readerClose: undefined, readerStatus: undefined,
        readerCloseSeen: false, readerStatusSeen: false, readerCloseAcknowledged: false};
      run.children.push(child);
      return Object.freeze({originalSource: Object.freeze({}),
        ...(project ? {retainChild(actual: PhysicalReader) {
          if (child.closed || child.closing || actual === null ||
              typeof actual !== 'object' && typeof actual !== 'function' ||
              child.reader !== undefined && child.reader !== actual) fail('InstalledSourcePreparationMismatch');
          // The installing Connector transfers its same acquired reader here,
          // before a callback/current check can reject the physical result.
          // This retains cleanup responsibility, never permission or capacity.
          child.reader = actual;
          captureReader(child);
          runFor(prepared);
        }} : {readOriginalBytes: () => readBytes(run, child)}),
        close: () => closeChild(child),
        status: () => Object.freeze({pending: !child.closed || child.flight !== undefined})});
    },
    prepareKeyedRead(prepared: object, declaration: object, originalRun: unknown, request: object) {
      const run = runFor(prepared) as Run & {producer: Producer};
      const model = run.model as InstalledEffectModelRun | undefined;
      const keyed = run.keyedPreparation;
      const plannedModel = run.effectful === true && run.purpose === 'source-compute' && model !== undefined;
      const plannedKeyed = run.effectful === true && run.purpose === 'source-compute' &&
        model === undefined && keyed !== undefined;
      const planned = plannedModel || plannedKeyed;
      const originalScope = model?.modelScope, members = model?.modelMembers, scopes = model?.modelScopes;
      const scopesCurrent = () => plannedKeyed
        ? run.keyedPreparation === keyed && run.model === undefined &&
          keyed!.requestIdentity !== undefined && run.producer.preparation?.effectPlan === run.operationPlan
        : members === undefined
        ? model!.modelMembers === undefined && model!.modelScope === originalScope && originalScope !== undefined
        : model!.modelMembers === members && model!.modelScopes === scopes &&
          Array.isArray(members) && Object.isFrozen(members) && members.length >= 2 &&
          Array.isArray(scopes) && Object.isFrozen(scopes) && scopes.length === members.length &&
          Array.isArray(model!.model?.components) && model!.model.components.length === members.length &&
          Array.isArray(model!.modelSelection?.components) && model!.modelSelection.components.length === members.length &&
          members.every((member, index) => member.modelScope === scopes[index] && scopes[index] !== undefined &&
            member.model === model!.model!.components![index] && member.modelSelection === model!.modelSelection!.components![index] &&
            member.modelScopeFinished !== true);
      if ((!project && !planned) || (plannedKeyed ? run.value !== originalRun || !scopesCurrent()
        : plannedModel ? run.value !== originalRun || model.value !== originalRun ||
          model.closed || model.prepared !== prepared || model.requestInput !== run.request ||
          model.original !== run.original || model.manager !== view || !scopesCurrent() ||
          model.operationPlan !== run.operationPlan || model.modelScopeFinished === true
        : run.purpose !== 'local-content' || run.original !== originalRun) ||
          !bundle!.sources.some(source => source.declaration === declaration) ||
          request === null || typeof request !== 'object' ||
          !planned && run.children.length >= run.required!.attempts ||
          run.children.some(child => child.request === request)) fail('InstalledSourcePreparationMismatch');
      if (planned) {
        const plan = plannedKeyed
          ? checked(run.producer.preparation!.context.runtime.clientProgramInstalledEffectManagedOperationPlan!(
            originalRun, prepared, keyed.requestIdentity))
          : checked(Reflect.apply(model!.readPlan!, model!.runtime, [originalRun, prepared, model!.request]));
        if (plan !== run.operationPlan || runFor(prepared) !== run || !scopesCurrent() ||
            (plannedModel && (model !== run.model || model.value !== originalRun || model.closed || model.modelScopeFinished === true))) {
          fail('InstalledSourcePreparationMismatch');
        }
      }
      const child: SourceReaderChild & {request: object} = {request, attempted: false, closed: false, bytes: undefined, flight: undefined,
        closing: false, cleanup: undefined, cleanupStatus: undefined, cleanupRetry: undefined,
        reader: undefined, readerClose: undefined, readerStatus: undefined,
        readerCloseSeen: false, readerStatusSeen: false, readerCloseAcknowledged: false};
      run.children.push(child);
      return Object.freeze({originalSource: Object.freeze({}), ...(project ? {retainChild(actual: PhysicalReader) {
        if (child.closed || child.closing || actual === null ||
            typeof actual !== 'object' && typeof actual !== 'function' ||
            child.reader !== undefined && child.reader !== actual) fail('InstalledSourcePreparationMismatch');
        child.reader = actual;
        captureReader(child);
        runFor(prepared);
      }} : {readOriginalBytes: () => readBytes(run, child)}), close: () => closeChild(child),
      status: () => Object.freeze({pending: !child.closed || child.flight !== undefined})});
    },
    async close() {
      if (closed) return status();
      if (flight !== undefined) return flight;
      closing = true;
      const work = Promise.resolve().then(async () => {
        // A failed before-snapshot call may not have returned its receipt to
        // the SDK. This installed owner still retains and retries that exact
        // initial child, rather than stranding it behind the producer gate.
        for (const producer of producers) if (producer.finished && producer.liveRuns === 0) {
          if (producer.preparation !== undefined) {
            if (producer.preparation.staticExplanationDelivery !== undefined ||
                producer.preparation.recovery?.childrenPending() === true) return status();
            cleanupOriginalRequestInput(producer.preparation, retireInitialPreparation);
            producer.preparation = undefined;
          }
          releaseFinishedProducer(producer);
        }
        if (producers.size !== 0) return status();
        let childPending = false, failure;
        for (const run of liveRuns) {
          if (!disposeOriginalExplanation(run.producer!.preparation)) childPending = true;
          for (const child of run.children) {
            try {if (pending(await closeChild(child))) childPending = true;}
            catch (cause) {childPending = true; failure ??= cause;}
          }
          if (run.original === undefined) continue;
          const observed = resourceRuntime.ordinaryManagedRunStatus(run.original);
          if (observed.admitted && !observed.stopped) childPending = true;
        }
        if (failure !== undefined) throw failure;
        if (childPending) return status();
        // The same successful installation cleanup also owns unfinished
        // preparation records which never obtained an original Run.
        for (const run of liveRuns) {
          const producer = run.producer!;
          if (producer.liveRuns < 1) fail('ForeignInstalledSourceProducer');
          producer.liveRuns--;
          liveRuns.delete(run);
          run.prepared = run.request = run.producer = undefined;
          run.model = run.content = run.required = run.fileIdentity = undefined;
          run.children = [];
          releaseFinishedProducer(producer);
        }
        if (producers.size !== 0) return status();
        bundle = undefined; liveRuns.clear(); closed = true; return status();
      });
      flight = work;
      try {return await work;} finally {if (flight === work) flight = undefined;}
    },
  });
  installations.set(view, {originals, source, current});
  current();
  try {
    if (source) {
      await callbacks.prepare!(originals, view);
      bundle = callbacks.read!(originals);
      // Retain the SAME initializer's complete inventory. It already owns its
      // construction and selected Project limits; a second count ceiling here
      // neither supplies backing nor changes the actual Request's demand.
      if (!Array.isArray(bundle.sources) || bundle.sources.length < 1) {
        fail('InstalledSourcePreparationMismatch');
      }
    }
    current(); return view;
  } catch (cause) {
    const error = Object.assign(new Error('InstalledSourcePreparationCleanupPending', {cause}),
      {code: 'InstalledSourcePreparationCleanupPending', cleanupPending: true}) as Error & {
        code: string; cleanupPending: boolean; cleanupHandle?: Readonly<{status: typeof status; retry: typeof view.close}>;
      };
    error.cleanupHandle = Object.freeze({status, retry: view.close});
    throw error;
  }
}
