// Bind the installed source-free compiler to the common Run and publication
// owner. Physical Local policy CIDs are stable identities of this Host profile.
import {runtimeField, runtimeOptionalField} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {checkedPublicationLimitValues} from './local-publication-limit-projection.mjs';
import {localContractLimits as limits} from './local-publication-limits.mjs';
import resultRecipe from './host-result-service-recipe.cjs';
import {withOriginalInferModelObservation} from './infer-effect-observation.mjs';
import {buildLocalPublicationPlan} from './local-publication-plan.mjs';
import {sourceFreeInferEffectPublicationPlan} from './local-source-free-effect-publication.mjs';
export {keyedInputRetentionSelection} from './local-publication-plan.mjs';
export {acquiredEffectPublicationAdmission, openSourceFreeEffectComputation,
  sourceFreeEffectPublicationPlan, sourceFreeEffectPublicationPlanOriginal,
  sourceFreeContentEffectPublicationPlan, sourceFreeInferEffectPublicationPlan}
  from './local-source-free-effect-publication.mjs';
export {inferTaskRunAdmission, selectRestoredInferOccurrence, restoreInferTaskRunAdmission,
  serializationTaskRunAdmission, selectInstalledSerializationGraph, serializationTaskPublicationPlan,
  inferTaskPublicationPlan} from './local-model-content-publication.mjs';
export {acquiredTaskPublicationPlan, acquiredMultiTaskPublicationPlan, acquiredKeyedTaskPublicationPlan}
  from './local-acquired-task-publication.mjs';
export {checkedLocalOutputLimits} from './local-publication-limit-projection.mjs';
export {prepareTimedClientInvocation} from './local-query-invocation.mjs';
export {localContractLimits, localOutputLimits} from './local-publication-limits.mjs';
export {acquiredTaskRunAdmission, sourceFreePlanOriginal, sourceFreePlanExplanation, sourceFreePlanExecutionOwner,
  sourceFreeTaskPlan, sourceFreeValuesAdmissionEvidence, sourceFreeValuesPlan} from './local-source-free-plan.mjs';

const {hostResultStorePolicy} = resultRecipe;

type SourceFreeInfer = Parameters<typeof sourceFreeInferEffectPublicationPlan>[0];
type InferAdmission = SourceFreeInfer['acquired'];
type Definition = InferAdmission['runDefinition'];
type Times = ReturnType<InferAdmission['selectRetention']>;
type OriginalModel = Readonly<{unit: number}>;
type ModelBinding = Readonly<{
  binding: unknown;
  observation: Definition & Readonly<{name: 'observation_set'}>;
  invocation: Definition & Readonly<{name: 'run_invocation'}>;
}>;
type ObserveModel = Parameters<typeof withOriginalInferModelObservation<unknown, OriginalModel>>[0];
type EffectLimits = typeof limits;
type SourceFacts = Readonly<{
  sourceEvidenceWire: string;
  inputLogicalWire: string;
  sourceRef: string;
  sourceContractCid: string;
  dataPolicyCid: string;
  authorityScopeCid: string;
  captureStartedAt: string;
  captureCompletedAt: string;
}>;
type ClauseSource = Readonly<{
  sourceRef: string; sourceContractCid: string; sourceDataPolicyCid: string;
}>;
type CapturedInput = Readonly<{
  inputKind?: string; occurrence?: Readonly<{stage?: number}>;
  checkedSource?: ClauseSource; requirement?: unknown; logicalInput?: unknown;
  identity: unknown; wholeCapacity?: unknown; capture: Readonly<{source(): unknown}>;
}>;
type Source = Readonly<{captured: CapturedInput; sourceEvidence?: unknown; sourceEvidenceWire?: string}>;
type KeyedEvidence = Readonly<{source: unknown; logicalRelationCid: string}>;
type KeyedFamily = Readonly<{sourceOriginal: unknown; lookup: unknown; evidence: KeyedEvidence}>;
type Window = Readonly<{captureStartedAt?: string; captureCompletedAt?: string}>;
type PublicationContext = Window & Readonly<{authorityScopeCid: string; dataPolicyCid: string}>;
type InstalledOriginals = Readonly<{managedRun?: unknown; sourcePlan?: unknown; sourceHost?: unknown; deferCatalogs?: boolean}>;
type SourceObservation = Readonly<{wire: string}>;
type Issued = Readonly<{observation: SourceObservation; invocation: unknown; owner: unknown; sourcePublication?: unknown}>;
type SourceEvidence = Readonly<{invocation: unknown; catalogBodies: readonly unknown[]}>;
type UnitValue = SourceEvidence;
type ModelResults = Readonly<{
  modelOriginal: OriginalModel; modelScan: unknown; modelReceipt: unknown;
  identityRetainedBytes: bigint; identityExecutionBytes: bigint;
}>;
type UnitEntry = {
  preparing: boolean; value?: UnitValue; modelOperation?: ModelOperation; results?: Partial<ModelResults>;
};
type CompletedUnit = UnitEntry & {results: ModelResults};
type UnitOwners = Readonly<{
  managedRun: unknown; sourcePlan: unknown; request: unknown;
  sources: readonly Source[]; inputs: unknown; retention: Definition; byUnit: Map<number, UnitEntry>;
}>;
type EffectMoon = InferAdmission['moon'] & ObserveModel['moon'] & {
  clientProgramCapturedSourceDependencyBodies(identity: unknown, source: unknown): unknown;
  clientProgramCapturedSourceLogicalCid(identity: unknown): string;
  clientProgramCapturedSourceSchemaCid(identity: unknown): string;
  clientProgramEffectCapturedSourceMatches(prepared: unknown, source: unknown): boolean;
  clientProgramEffectPublicationDataPolicyCid(prepared: unknown): string | undefined;
  clientProgramEffectPublicationPolicyBodies(prepared: unknown, bytes: number, nodes: number, depth: number): unknown;
  clientProgramEffectPublicationPolicyBodiesDeferredCatalog(prepared: unknown, bytes: number, nodes: number, depth: number): unknown;
  clientProgramInstalledEffectPublicationLimits(run: unknown, prepared: unknown, request: unknown,
    plan: unknown, maxObjectBytes: number): unknown;
};
type EffectControl = InferAdmission['control'] & {
  admitRunEvidence(kind: 'source_evidence', wire: string, bounds: EffectLimits): unknown;
  issueCheckedInstalledEffectKeyedInvocation(run: unknown, prepared: unknown, request: unknown,
    plan: unknown, sourceHost: unknown, compilation: object, admission: unknown, definition: unknown,
    lookup: unknown, started: string | undefined, completed: string | undefined, bounds: EffectLimits): Issued;
  prepareInstalledEffectKeyedSourceUnit(run: unknown, prepared: unknown, request: unknown,
    plan: unknown, sourceHost: unknown, source: unknown, lookup: unknown,
    retention: Definition, bounds: EffectLimits, deferCatalogs: boolean): SourceEvidence;
  issueCheckedClientEffectCapturedInvocation(prepared: unknown, compilation: object, admission: unknown,
    definition: unknown, source: unknown, facts: SourceFacts, bounds: EffectLimits): Issued;
  issueCheckedInstalledEffectCapturedInvocation(run: unknown, prepared: unknown, request: unknown,
    plan: unknown, sourceHost: unknown, compilation: object, admission: unknown, definition: unknown,
    source: unknown, facts: SourceFacts, bounds: EffectLimits): Issued;
  issueCheckedClientSerializationInvocation(compiled: unknown, definition: Definition,
    generation: unknown, bounds: EffectLimits): Issued;
  issueCheckedInstalledEffectContentInvocation(run: unknown, prepared: unknown, request: unknown, plan: unknown,
    sourceHost: unknown, compilation: object, admission: unknown, definition: unknown, compiled: unknown,
    generation: unknown, bounds: EffectLimits): Issued;
  rebindInstalledEffectResultRetention(run: unknown, prepared: unknown, request: unknown, plan: unknown,
    retention: Definition, dataPolicyCid: string, bounds: EffectLimits): Definition;
  issueCheckedWholeEffectSourceUnit(plan: unknown, prepared: unknown, request: unknown, slot: number,
    original: unknown, identity: unknown, capacity: unknown, logicalInput: unknown, evidence: unknown,
    scopeCid: string, retention: Definition, bounds: EffectLimits, deferCatalogs: boolean): UnitValue;
  issueCheckedAcquiredEffectEvidence(prepared: unknown, original: unknown, identity: unknown, requirement: unknown,
    logicalInput: unknown, evidence: unknown, scopeCid: string, dataPolicyCid: string,
    sourceRetention: Definition, bounds: EffectLimits, unit: number, retention: Definition, deferCatalogs: boolean): UnitValue;
  prepareCheckedInstalledEffectSourceUnits(plan: unknown, prepared: unknown, request: unknown,
    compilation: object, admission: unknown, definition: unknown, sources: readonly Source[], evidence: readonly unknown[],
    context: PublicationContext, bounds: EffectLimits): unknown;
  prepareInstalledEffectModelSourceUnit(run: unknown, plan: unknown, request: unknown, inputs: unknown,
    unit: number, retention: Definition, bounds: EffectLimits, deferCatalogs: boolean): UnitValue;
  issueCheckedInstalledEffectDirectSourcesInvocation(plan: unknown, prepared: unknown, request: unknown,
    compilation: object, admission: unknown, definition: unknown, sources: readonly Source[], evidence: readonly unknown[],
    context: PublicationContext, bounds: EffectLimits): Issued;
  issueCheckedOriginalEffectDirectSourcesInvocation(run: unknown, prepared: unknown, request: unknown, plan: unknown,
    sourceHost: unknown, compilation: object, admission: unknown, definition: unknown, sources: readonly Source[],
    evidence: readonly unknown[], context: PublicationContext, bounds: EffectLimits): Issued;
  issueCheckedClientEffectMultiCapturedInvocation(prepared: unknown, compilation: object, admission: unknown,
    definition: unknown, sources: readonly Source[], context: PublicationContext, bounds: EffectLimits): Issued;
  issueCheckedInstalledEffectMultiCapturedInvocation(run: unknown, prepared: unknown, request: unknown, plan: unknown,
    sourceHost: unknown, compilation: object, admission: unknown, definition: unknown, sources: readonly Source[],
    context: PublicationContext, bounds: EffectLimits): Issued;
  prepareCombinedEffectSourceUnit(publication: unknown, unit: number, retention: Definition,
    bounds: EffectLimits, deferCatalogs: boolean): UnitValue;
  captureCheckedClientInferModelObservation(issued: ModelBinding, scan: unknown, receipt: unknown,
    bounds: EffectLimits, earlier?: UnitValue): OriginalModel;
};
type Acquired = Omit<InferAdmission, 'control' | 'moon'> & Readonly<{moon: EffectMoon; control: EffectControl}>;
type EffectOptions = InstalledOriginals & Window & Readonly<{acquired: Acquired}>;
type KeyedOptions = EffectOptions & Readonly<{sources: readonly Source[]; keyedFamily: KeyedFamily}>;
type DirectOptions = EffectOptions & Readonly<{
  captured: CapturedInput; sourceEvidence?: unknown; sourceEvidenceWire: string;
  content?: Readonly<{compiled: unknown; generation: unknown}>;
}>;
type UnitAcquired = Pick<Acquired,
  'prepared' | 'requestIdentity' | 'selectRetention' | 'compilation' | 'admission' | 'definition' | 'authorityScopeCid'> & Readonly<{
  moon: Pick<EffectMoon, 'clientProgramEffectPublicationDataPolicyCid'>;
  control: Pick<EffectControl, 'issueInstalledEffectInitialRetention' | 'admitRunEvidence' |
    'prepareCheckedInstalledEffectSourceUnits' | 'prepareInstalledEffectModelSourceUnit'>;
}>;
type UnitOptions = InstalledOriginals & Readonly<{
  acquired: UnitAcquired; sources: readonly Source[]; modelUnits: readonly number[];
}>;
type PluralOptions = EffectOptions & Readonly<{
  sources: readonly Source[]; issuedModel?: ModelBinding; modelOriginal?: OriginalModel;
  modelOriginals?: readonly OriginalModel[]; modelEvidence?: readonly unknown[];
  keyedSource?: KeyedEvidence; sourceUnitsOriginal?: UnitOwners;
}>;
type ModelOperation = ObserveModel['operation'] & Readonly<{
  bindIssuedInvocation(...args: Parameters<SourceFreeInfer['operation']['bindIssuedInvocation']>): ModelBinding;
  contentGenerations?(): readonly unknown[] | undefined;
}>;
type ModelOptions = EffectOptions & Readonly<{
  sources: readonly Source[]; compiled: unknown; operation: ModelOperation;
  operations?: readonly ModelOperation[]; issuance: unknown; modelEvidence: readonly unknown[];
  keyedSource?: KeyedEvidence; signal?: AbortSignal; sourceUnitsOriginal?: UnitOwners;
  fundingOperation?: ModelOperation; current?: () => unknown; retainBinding?: (binding: unknown) => unknown;
}>;

// One real captured Source and its completed keyed right input form the same
// checked Unit. Neither side is relabeled as Model or a single-Source result.
export function acquiredKeyedEffectPublicationPlan({acquired, sources, keyedFamily,
  captureStartedAt, captureCompletedAt, sourcePlan, managedRun, sourceHost,
  deferCatalogs = false}: KeyedOptions, keyedDefinition?: unknown) {
  const {moon, control, prepared, compilation, admission,
    runDefinition, compiledPlan, authorityScopeCid, namespaceId, storeAuthorityCid, now} = acquired;
  if (sources.length !== 1 || keyedFamily?.sourceOriginal === undefined ||
      keyedFamily.lookup === undefined || managedRun === undefined || keyedDefinition === undefined) {
    throw new TypeError('InvalidOriginalEffectKeyedPublication');
  }
  // The caller borrows this exact Definition view from its existing keyed
  // preparation. The Core operation Plan is opaque and supplies no JS fields.
  const {observation, invocation, owner: invocationOwner} =
    control.issueCheckedInstalledEffectKeyedInvocation(managedRun, prepared,
      acquired.requestIdentity, sourcePlan, sourceHost, compilation, admission, keyedDefinition,
      keyedFamily.lookup, captureStartedAt, captureCompletedAt, limits);
  const run = JSON.parse(runDefinition.wire) as {created_at: string; valid_until: string};
  const {plan, retention, retentionDependencies} = buildLocalPublicationPlan({
    control, admission, runDefinition, invocation, observation,
    compiledPlanCid: compiledPlan.identity,
    programDefinitionCid: moon.clientProgramEffectDefinitionCid(prepared),
    inputRelationCids: [...new Set([
      moon.clientProgramCapturedSourceLogicalCid(sources[0].captured.identity),
      keyedFamily.evidence.logicalRelationCid])],
    sourceEvidence: [sources[0].sourceEvidence, keyedFamily.evidence.source],
    authorityScopeCid, namespaceId, storeAuthorityCid,
    dataPolicyCid: (JSON.parse(observation.wire) as {data_policy_cid: string}).data_policy_cid,
    createdAt: run.created_at, now, retainUntil: run.valid_until,
    resultCount: moon.clientProgramEffectCompilationResultNames(compilation).length,
    moon, effectCompilation: compilation, preparedEffect: prepared,
    outputLimits: checkedPublicationLimitValues(moon.clientProgramInstalledEffectPublicationLimits(
      managedRun, prepared, acquired.requestIdentity, sourcePlan, hostResultStorePolicy.maxObjectBytes)),
    retentionSelection: acquired.selectRetention?.(),
    originalRetention: (managedRun === undefined ? undefined : control.issueInstalledEffectInitialRetention(managedRun, prepared,
      acquired.requestIdentity, sourcePlan, (JSON.parse(observation.wire) as {data_policy_cid: string}).data_policy_cid, acquired.selectRetention(), limits))});
  const acquiredEvidence = control.prepareInstalledEffectKeyedSourceUnit(managedRun,
    prepared, acquired.requestIdentity, sourcePlan, sourceHost, keyedFamily.sourceOriginal,
    keyedFamily.lookup, retention, limits, deferCatalogs);
  return Object.freeze({...plan, effectInputRetention: retention, invocationOwner,
    localEvidenceContext: Object.freeze({admission, runDefinition,
      ...(deferCatalogs ? {catalogDeferred: true} : {}),
      acquiredEvidence, retentionDependencies, acquisitionDependencies: Object.freeze([]),
      sourceLocalInvocation: acquiredEvidence.invocation,
      runInvocation: invocation, observation})});
}

export function acquiredEffectPublicationPlan({acquired, captured,
  sourceEvidence: originalSourceEvidence, sourceEvidenceWire,
  captureStartedAt, captureCompletedAt, content, sourcePlan, managedRun, sourceHost, deferCatalogs = false}: DirectOptions) {
  if (content === undefined && captured?.inputKind === 'whole-input') {
    return acquiredMultiEffectPublicationPlan({acquired,
      sources: [{captured, sourceEvidence: originalSourceEvidence, sourceEvidenceWire}],
      captureStartedAt, captureCompletedAt, sourcePlan, managedRun, sourceHost, deferCatalogs});
  }
  const {moon, control, prepared, compilation, definition, admission,
    runDefinition, compiledPlan, authorityScopeCid,
    namespaceId, storeAuthorityCid, now} = acquired;
  const whole = captured?.inputKind === 'whole-input';
  if (typeof sourceEvidenceWire !== 'string' ||
      typeof captureStartedAt !== 'string' ||
      typeof captureCompletedAt !== 'string' ||
      captured?.logicalInput === undefined ||
      captured?.checkedSource === undefined ||
      captured?.identity === undefined ||
      (whole ? captured.wholeCapacity === undefined || sourcePlan === undefined ||
        acquired.requestIdentity === undefined : captured?.requirement === undefined) ||
      captured?.capture === undefined ||
      moon.clientProgramEffectCapturedSourceMatches(prepared,
        captured.capture.source()) !== true) {
    throw new TypeError('InvalidAcquiredEffectPublication');
  }
  const source = captured.checkedSource;
  const sourceFacts = {sourceEvidenceWire,
    inputLogicalWire: moon.strategyRunEvidenceJson(captured.logicalInput),
    sourceRef: source.sourceRef, sourceContractCid: source.sourceContractCid,
    authorityScopeCid, dataPolicyCid: source.sourceDataPolicyCid, captureStartedAt, captureCompletedAt};
  const {observation, invocation, owner: invocationOwner} = content === undefined
    ? managedRun === undefined
      ? control.issueCheckedClientEffectCapturedInvocation(prepared, compilation, admission,
        definition, captured.capture.source(), sourceFacts, limits)
      : control.issueCheckedInstalledEffectCapturedInvocation(managedRun, prepared,
        acquired.requestIdentity, sourcePlan, sourceHost, compilation, admission, definition,
        captured.capture.source(), sourceFacts, limits)
    : managedRun === undefined
      ? control.issueCheckedClientSerializationInvocation(content.compiled, runDefinition, content.generation, limits)
      : control.issueCheckedInstalledEffectContentInvocation(managedRun, prepared,
        acquired.requestIdentity, sourcePlan, sourceHost, compilation, admission, definition,
        content.compiled, content.generation, limits);
  const sourceEvidence = control.admitRunEvidence('source_evidence',
    sourceEvidenceWire, limits);
  const dataPolicyCid = content === undefined ? source.sourceDataPolicyCid
    : (JSON.parse(observation.wire) as {data_policy_cid: string}).data_policy_cid;
  const run = JSON.parse(runDefinition.wire) as {created_at: string; valid_until: string};
  const resultCount = moon.clientProgramEffectCompilationResultNames(
    compilation).length;
  const {plan, retention, retentionDependencies} = buildLocalPublicationPlan({
    control, admission,
    runDefinition, invocation, observation, compiledPlanCid: compiledPlan.identity,
    programDefinitionCid: moon.clientProgramEffectDefinitionCid(prepared),
    inputRelationCids: [moon.clientProgramCapturedSourceLogicalCid(
      captured.identity)], sourceEvidence: [sourceEvidence],
    authorityScopeCid, namespaceId, storeAuthorityCid,
    dataPolicyCid, createdAt: run.created_at,
    now, resultCount, retainUntil: run.valid_until,
    moon, effectCompilation: compilation, preparedEffect: prepared,
    retentionSelection: acquired.selectRetention?.(),
    originalRetention: (managedRun === undefined ? undefined : control.issueInstalledEffectInitialRetention(managedRun, prepared,
      acquired.requestIdentity, sourcePlan, dataPolicyCid, acquired.selectRetention(), limits))});
  let sourceRetention = retention;
  if (content !== undefined && !whole) {
    sourceRetention = control.rebindInstalledEffectResultRetention(
      managedRun, prepared, acquired.requestIdentity, sourcePlan, retention,
      source.sourceDataPolicyCid, limits);
  }
  const acquiredEvidence = whole
    ? control.issueCheckedWholeEffectSourceUnit(sourcePlan, prepared, acquired.requestIdentity,
      0, captured.capture.source(), captured.identity, captured.wholeCapacity,
      captured.logicalInput, sourceEvidence, authorityScopeCid, retention, limits, deferCatalogs)
    : control.issueCheckedAcquiredEffectEvidence(
      prepared, captured.capture.source(), captured.identity,
      captured.requirement, captured.logicalInput, sourceEvidence,
      authorityScopeCid, source.sourceDataPolicyCid, sourceRetention, limits, 0, retention, deferCatalogs);
  const inputBodies = moon.clientProgramCapturedSourceDependencyBodies(
    captured.identity, captured.capture.source());
  if (typeof runtimeOptionalField(inputBodies, 0) !== 'string' ||
      typeof runtimeOptionalField(inputBodies, 1) !== 'string') {
    throw new Error('MissingCapturedEffectSourceBodies');
  }
  const acquisitionDependencies = Object.freeze([
    Object.freeze({kind: 'relation_value',
      cid: moon.clientProgramCapturedSourceLogicalCid(captured.identity),
      wire: runtimeField(inputBodies, 0)}),
    Object.freeze({kind: 'relation_schema',
      cid: moon.clientProgramCapturedSourceSchemaCid(captured.identity),
      wire: runtimeField(inputBodies, 1)}),
  ]);
  const contentGenerations = content === undefined ? undefined : Object.freeze([content.generation]);
  return Object.freeze({...plan, effectInputRetention: retention, invocationOwner,
    ...(contentGenerations === undefined ? {} : {
      receiptEvidence: Object.freeze({...plan.receiptEvidence, contentGenerations}),
      captureEvidence: Object.freeze({...plan.captureEvidence, contentGenerations})}),
    localEvidenceContext: Object.freeze({admission, runDefinition,
      ...(deferCatalogs ? {catalogDeferred: true} : {}),
      acquiredEvidence, retentionDependencies, acquisitionDependencies,
      ...(content === undefined ? {} : {acquiredCatalogBodies: Object.freeze([
        ...acquiredEvidence.catalogBodies,
        ...(checked((deferCatalogs ? moon.clientProgramEffectPublicationPolicyBodiesDeferredCatalog : moon.clientProgramEffectPublicationPolicyBodies)(prepared,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth)) as readonly unknown[]).map(body =>
          Object.freeze({kind: runtimeField(body, 0), cid: runtimeField(body, 1), wire: runtimeField(body, 2)})),
      ])}),
      sourceLocalInvocation: acquiredEvidence.invocation,
      runInvocation: invocation, observation})});
}

// Retain the actual upstream Unit semantics before opening the first Model.
// The existing group owns this cache and its dispatch borrow through cleanup;
// no complete Model/Run observation or physical publication is claimed here.
export function prepareAcquiredEffectSourceUnits({acquired, sources, sourcePlan, managedRun, modelUnits, deferCatalogs = false}: UnitOptions) {
  if (!Array.isArray(sources) || !Array.isArray(modelUnits)) {
    throw new TypeError('WholeEffectProducerUnitOriginalRequired');
  }
  const units = new Map<number, number>();
  for (const {captured} of sources) {
    const unit = captured.occurrence?.stage as number;
    if (!Number.isSafeInteger(unit) || unit < 0) throw new TypeError('OriginalEffectSourceCoordinateRequired');
    units.set(unit, (units.get(unit) ?? 0) + 1);
  }
  const selected = [...units].filter(([unit, count]) => count > 1 && !modelUnits.includes(unit));
  if (selected.length === 0) return undefined;
  if (managedRun === undefined || sourcePlan === undefined || acquired.requestIdentity === undefined) {
    throw new TypeError('WholeEffectProducerUnitOriginalRequired');
  }
  const {moon, control} = acquired;
  const policy = moon.clientProgramEffectPublicationDataPolicyCid(acquired.prepared);
  if (typeof policy !== 'string') throw new TypeError('UnavailableAcquiredEffectPolicy');
  const retention = control.issueInstalledEffectInitialRetention(managedRun, acquired.prepared,
    acquired.requestIdentity, sourcePlan, policy, acquired.selectRetention(), limits);
  const evidence = sources.map(source => source.sourceEvidence === undefined
    ? control.admitRunEvidence('source_evidence', source.sourceEvidenceWire!, limits) : source.sourceEvidence);
  const inputs = control.prepareCheckedInstalledEffectSourceUnits(sourcePlan, acquired.prepared,
    acquired.requestIdentity, acquired.compilation, acquired.admission, acquired.definition,
    sources, evidence, {authorityScopeCid: acquired.authorityScopeCid, dataPolicyCid: policy}, limits);
  const byUnit = new Map<number, UnitEntry>();
  for (const [unit] of selected) {
    // This record is installed before the Resource current/resize callbacks.
    // Reentry or a failed constructor never obtains a second original body.
    const entry: UnitEntry = {preparing: true, value: undefined};
    byUnit.set(unit, entry);
    entry.value = control.prepareInstalledEffectModelSourceUnit(managedRun, sourcePlan,
      acquired.requestIdentity, inputs, unit, retention, limits, deferCatalogs);
    entry.preparing = false;
  }
  return Object.freeze({managedRun, sourcePlan, request: acquired.requestIdentity,
    sources, inputs, retention, byUnit});
}

// Both acquired tuples remain checked by the common Effect owner. Source
// input retention carries each original policy; derived publication carries
// the checked combined policy with exactly the same custody/time bounds.
export function acquiredMultiEffectPublicationPlan({acquired, sources,
  captureStartedAt, captureCompletedAt, issuedModel, modelOriginal, modelOriginals = modelOriginal === undefined ? [] : [modelOriginal], modelEvidence = [], keyedSource, sourcePlan, managedRun, sourceHost, sourceUnitsOriginal, deferCatalogs = false}: PluralOptions) {
  const {moon, control, prepared, compilation, definition, admission,
    runDefinition, compiledPlan, authorityScopeCid,
    namespaceId, storeAuthorityCid, now} = acquired;
  if (!Array.isArray(sources) || sources.length < 1) {
    throw new TypeError('IncompleteAcquiredEffectSources');
  }
  if (!Array.isArray(modelOriginals) || issuedModel !== undefined && (modelOriginals.length === 0 ||
      modelOriginals.some(model => !Number.isSafeInteger(model?.unit) || model.unit < 0) ||
      new Set(modelOriginals.map(model => model.unit)).size !== modelOriginals.length)) {
    throw new TypeError('OriginalEffectModelObservationRequired');
  }
  const dataPolicyCid = moon.clientProgramEffectPublicationDataPolicyCid(prepared);
  if (typeof dataPolicyCid !== 'string') {
    throw new TypeError('UnavailableAcquiredEffectPolicy');
  }
  const sourceEvidence = sources.map(source => source.sourceEvidence === undefined
    ? control.admitRunEvidence('source_evidence', source.sourceEvidenceWire!, limits)
    : source.sourceEvidence);
  const sourceUnits = new Map<number, number>();
  for (const {captured} of sources) {
    const unit = captured.occurrence?.stage as number;
    if (!Number.isSafeInteger(unit) || unit < 0) {
      throw new TypeError('OriginalEffectSourceCoordinateRequired');
    }
    sourceUnits.set(unit, (sourceUnits.get(unit) ?? 0) + 1);
  }
  const whole = issuedModel === undefined &&
    sources.some(({captured}) => captured.inputKind === 'whole-input');
  const direct = issuedModel === undefined && (whole || [...sourceUnits.values()].some(count => count > 1));
  if (direct && (sourcePlan === undefined || acquired.requestIdentity === undefined)) {
    throw new TypeError('WholeEffectProducerUnitOriginalRequired');
  }
  const context = {authorityScopeCid, dataPolicyCid, captureStartedAt, captureCompletedAt};
  const {observation, invocation, owner: invocationOwner, sourcePublication}: Issued = direct
    ? managedRun === undefined
      ? control.issueCheckedInstalledEffectDirectSourcesInvocation(sourcePlan, prepared,
        acquired.requestIdentity, compilation, admission, definition, sources, sourceEvidence, context, limits)
      : control.issueCheckedOriginalEffectDirectSourcesInvocation(managedRun, prepared,
        acquired.requestIdentity, sourcePlan, sourceHost, compilation, admission, definition,
        sources, sourceEvidence, context, limits)
    : issuedModel === undefined
      ? managedRun === undefined
        ? control.issueCheckedClientEffectMultiCapturedInvocation(prepared, compilation, admission,
          definition, sources, context, limits)
        : control.issueCheckedInstalledEffectMultiCapturedInvocation(managedRun, prepared,
          acquired.requestIdentity, sourcePlan, sourceHost, compilation, admission, definition,
          sources, context, limits)
      : managedRun === undefined
        ? control.checkedClientEffectInferInvocation(prepared, compilation, runDefinition, issuedModel)
        : control.bindCheckedInstalledEffectModelInvocation(managedRun, prepared,
          acquired.requestIdentity, sourcePlan, sourceHost, compilation, admission, definition, issuedModel);
  // Source Unit semantics remain available with later Models present. This
  // retains only original Source inputs, never a fake complete Run observation.
  const needsSourceUnits = issuedModel !== undefined && [...sourceUnits].some(([unit, count]) =>
    count > 1 && !modelOriginals.some(model => model.unit === unit));
  if (needsSourceUnits && (sourcePlan === undefined || managedRun === undefined || acquired.requestIdentity === undefined)) {
    throw new TypeError('WholeEffectProducerUnitOriginalRequired');
  }
  if (sourceUnitsOriginal !== undefined && (sourceUnitsOriginal.managedRun !== managedRun ||
      sourceUnitsOriginal.sourcePlan !== sourcePlan || sourceUnitsOriginal.request !== acquired.requestIdentity ||
      sourceUnitsOriginal.sources !== sources)) throw new TypeError('ForeignEffectSourceUnitOriginal');
  const sourceUnitInputs = !needsSourceUnits ? undefined : sourceUnitsOriginal?.inputs ??
    control.prepareCheckedInstalledEffectSourceUnits(sourcePlan, prepared,
      acquired.requestIdentity, compilation, admission, definition, sources, sourceEvidence, context, limits);
  if (keyedSource !== undefined) {
    if (issuedModel === undefined || keyedSource.source === undefined ||
        typeof keyedSource.logicalRelationCid !== 'string') throw new TypeError('IncompleteAcquiredEffectSources');
    sourceEvidence.push(keyedSource.source);
  }
  const run = JSON.parse(runDefinition.wire) as {created_at: string; valid_until: string};
  const {plan, retention, retentionDependencies} = buildLocalPublicationPlan({
    control, admission, runDefinition, invocation, observation,
    compiledPlanCid: compiledPlan.identity,
    programDefinitionCid: moon.clientProgramEffectDefinitionCid(prepared),
    // Result derivation names a set of logical dependencies. Equal content
    // does not merge the original Source occurrences or their evidence above.
    inputRelationCids: [...new Set([...sources.map(({captured}) =>
      moon.clientProgramCapturedSourceLogicalCid(captured.identity)),
      ...(keyedSource === undefined ? [] : [keyedSource.logicalRelationCid])])],
    sourceEvidence, modelEvidence, authorityScopeCid, namespaceId, storeAuthorityCid,
    dataPolicyCid, createdAt: run.created_at, now,
    resultCount: moon.clientProgramEffectCompilationResultNames(compilation).length,
    retainUntil: run.valid_until,
    moon, effectCompilation: compilation, preparedEffect: prepared,
    retentionSelection: acquired.selectRetention?.(), originalRetention: sourceUnitsOriginal?.retention ??
      (managedRun === undefined ? undefined : control.issueInstalledEffectInitialRetention(managedRun, prepared,
      acquired.requestIdentity, sourcePlan, dataPolicyCid, acquired.selectRetention(), limits))});
  const acquisitionDependencies = [];
  const acquiredEvidenceByUnit: UnitValue[] = [];
  for (const [slot, {captured}] of sources.entries()) {
    const unit = captured.occurrence?.stage as number;
    if (!Number.isSafeInteger(unit) || unit < 0) {
      throw new TypeError('OriginalEffectSourceCoordinateRequired');
    }
    // Inline Query/Whole inputs contribute to this SAME Model Unit. Their
    // complete evidence is issued from its retained Model observation below,
    // never through the Query-only single-Source Unit entrance.
    const modelContribution = issuedModel !== undefined && modelOriginals.some(model => model.unit === unit);
    if (!modelContribution && sourceUnits.get(unit)! > 1) {
      if (acquiredEvidenceByUnit[unit] === undefined) {
        if (sourceUnitInputs !== undefined) {
          const original = sourceUnitsOriginal?.byUnit.get(unit);
          if (sourceUnitsOriginal !== undefined && (original === undefined || original.preparing || original.value === undefined)) {
            throw new TypeError('OriginalEffectSourceUnitUnavailable');
          }
          acquiredEvidenceByUnit[unit] = original?.value ?? control.prepareInstalledEffectModelSourceUnit(
            managedRun, sourcePlan, acquired.requestIdentity, sourceUnitInputs, unit, retention, limits, deferCatalogs);
        } else {
          if (sourcePublication === undefined) {
            throw new TypeError('CombinedEffectProducerUnitOriginalRequired');
          }
          acquiredEvidenceByUnit[unit] = control.prepareCombinedEffectSourceUnit(
            sourcePublication, unit, retention, limits, deferCatalogs);
        }
      }
    } else if (!modelContribution) {
      if (acquiredEvidenceByUnit[unit] !== undefined) {
        throw new TypeError('DuplicateEffectProducerUnitEvidence');
      }
      if (captured.inputKind === 'whole-input') {
        if (sourcePlan === undefined || acquired.requestIdentity === undefined ||
            captured.wholeCapacity === undefined) {
          throw new TypeError('WholeEffectProducerUnitOriginalRequired');
        }
        acquiredEvidenceByUnit[unit] = control.issueCheckedWholeEffectSourceUnit(
          sourcePlan, prepared, acquired.requestIdentity, slot,
          captured.capture.source(), captured.identity, captured.wholeCapacity,
          captured.logicalInput, sourceEvidence[slot], authorityScopeCid, retention, limits, deferCatalogs);
      } else {
        if (captured.requirement === undefined) {
          throw new TypeError('QueryEffectProducerUnitOriginalRequired');
        }
        const sourceRetention = control.rebindInstalledEffectResultRetention(
          managedRun, prepared, acquired.requestIdentity, sourcePlan, retention,
          captured.checkedSource!.sourceDataPolicyCid, limits);
        acquiredEvidenceByUnit[unit] = control.issueCheckedAcquiredEffectEvidence(
          prepared, captured.capture.source(), captured.identity,
          captured.requirement, captured.logicalInput, sourceEvidence[slot],
          authorityScopeCid, captured.checkedSource!.sourceDataPolicyCid,
          sourceRetention, limits, unit, retention, deferCatalogs);
      }
    }
    const bodies = moon.clientProgramCapturedSourceDependencyBodies(
      captured.identity, captured.capture.source());
    if (typeof runtimeOptionalField(bodies, 0) !== 'string' || typeof runtimeOptionalField(bodies, 1) !== 'string') {
      throw new Error('MissingCapturedEffectSourceBodies');
    }
    acquisitionDependencies.push(
      Object.freeze({kind: 'relation_value',
        cid: moon.clientProgramCapturedSourceLogicalCid(captured.identity),
        wire: runtimeField(bodies, 0)}),
      Object.freeze({kind: 'relation_schema',
        cid: moon.clientProgramCapturedSourceSchemaCid(captured.identity),
        wire: runtimeField(bodies, 1)}));
  }
  return Object.freeze({...plan, effectInputRetention: retention, invocationOwner,
    localEvidenceContext: Object.freeze({admission, runDefinition,
      ...(deferCatalogs ? {catalogDeferred: true} : {}),
      acquiredEvidence: acquiredEvidenceByUnit[0],
      acquiredEvidenceByUnit: Object.freeze(acquiredEvidenceByUnit),
      ...(sourceUnitsOriginal === undefined ? {} : {originalUnitResults: sourceUnitsOriginal.byUnit}),
      ...(modelOriginals.length === 0 ? {} : {
        modelOriginalByUnit: Object.freeze(Object.fromEntries(modelOriginals.map(model => [model.unit, model]))),
        modelRetention: retention,
      }),
      acquiredCatalogBodies: Object.freeze([
        ...acquiredEvidenceByUnit.flatMap(value => value.catalogBodies),
        ...(checked((deferCatalogs ? moon.clientProgramEffectPublicationPolicyBodiesDeferredCatalog : moon.clientProgramEffectPublicationPolicyBodies)(prepared,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth)) as readonly unknown[]).map(body =>
          Object.freeze({kind: runtimeField(body, 0), cid: runtimeField(body, 1), wire: runtimeField(body, 2)})),
      ]),
      retentionDependencies,
      acquisitionDependencies: Object.freeze(acquisitionDependencies),
      runInvocation: invocation, observation})});
}

// The original Model issuer has already adopted the real capture into the
// original Effect Run. Its live binding remains held by capture custody.
export async function acquiredInferEffectPublicationPlan({acquired, sources,
  compiled, operation, operations = [operation], issuance, modelEvidence,
  captureStartedAt, captureCompletedAt, keyedSource, signal, sourcePlan, managedRun, sourceHost, sourceUnitsOriginal, fundingOperation = operation, current, retainBinding, deferCatalogs = false}: ModelOptions) {
  if (!Array.isArray(operations) || operations.length === 0 || operations[0] !== operation ||
      new Set(operations).size !== operations.length) {
    throw new TypeError('OriginalEffectModelInventoryRequired');
  }
  const issuedModels: ModelBinding[] = [], modelOriginals: OriginalModel[] = [];
  // Earlier Model scans stay in this group's original custody; count that
  // retained overlap before constructing any later final-issuer metadata.
  const earlierUnits = [...(sourceUnitsOriginal?.byUnit.values() ?? [])]
    .filter((entry): entry is CompletedUnit => entry.results?.modelOriginal !== undefined);
  let retainedBase = earlierUnits.reduce((sum, entry) => sum + entry.results.identityRetainedBytes, 0n);
  let executionBase = earlierUnits.reduce((sum, entry) => sum + entry.results.identityExecutionBytes, 0n);
  try {
    for (const originalOperation of operations) {
      current?.(); signal?.throwIfAborted();
      const issued = originalOperation.bindIssuedInvocation(acquired.control, {
        compiled, runDefinition: acquired.runDefinition, issued: issuance});
      issuedModels.push(issued);
      retainBinding?.(issued.binding);
      const earlier = earlierUnits.find(entry => entry.modelOperation === originalOperation);
      const model = earlier === undefined ? await withOriginalInferModelObservation({
        moon: acquired.moon, operation: fundingOperation, binding: issued.binding, signal, retainedBase, executionBase,
        consume: ({scan, receipt, retainedBytes, executionBytes}) => {
          const original = acquired.control.captureCheckedClientInferModelObservation(issued, scan, receipt, limits);
          retainedBase += retainedBytes; executionBase += executionBytes;
          return original;
        },
      }) : acquired.control.captureCheckedClientInferModelObservation(issued,
        earlier.results.modelScan, earlier.results.modelReceipt, limits, earlier.value);
      current?.(); signal?.throwIfAborted();
      if (!Number.isSafeInteger(model?.unit) || model.unit < 0 ||
          modelOriginals.some(original => original.unit === model.unit)) {
        throw new TypeError('OriginalEffectModelUnitInventoryRequired');
      }
      modelOriginals.push(model);
    }
    const issued = issuedModels[0];
    const plan = sources.length === 0
      ? sourceFreeInferEffectPublicationPlan({acquired, compiled, operation, issuance,
        issuedModel: issued, modelOriginals, modelEvidence, managedRun, sourcePlan, sourceHost}).plan
      : acquiredMultiEffectPublicationPlan({acquired, sources,
        captureStartedAt, captureCompletedAt, issuedModel: issued, modelOriginals, modelEvidence, keyedSource,
        sourcePlan, managedRun, sourceHost, sourceUnitsOriginal, deferCatalogs});
    const generations = operations.flatMap(original => original.contentGenerations?.() ?? []);
    const completePlan = generations.length === 0 ? plan : Object.freeze({...plan,
      receiptEvidence: Object.freeze({...plan.receiptEvidence, contentGenerations: generations}),
      captureEvidence: Object.freeze({...plan.captureEvidence, contentGenerations: generations})});
    return Object.freeze({...issued, bindings: Object.freeze(issuedModels.map(original => original.binding)), plan: completePlan});
  } catch (error) {
    // Group custody retains each original binding before the first await. A
    // standalone caller transfers no such custody, so retire its partials here.
    if (retainBinding === undefined) {
      for (const issued of issuedModels) {
        try {acquired.moon.clientProgramReleaseInferInvocationBinding(issued.binding);} catch { /* Preserve the primary. */ }
      }
    }
    throw error;
  }
}
