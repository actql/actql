import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {localContractLimits as limits} from './local-publication-limits.mjs';
import {buildLocalPublicationPlan, effectPublicationAdmission} from './local-publication-plan.mjs';

type AdmissionInput = Parameters<typeof effectPublicationAdmission>[0];
type Admission = ReturnType<typeof effectPublicationAdmission>;
type Definition = Admission['runDefinition'];
type EffectBounds = typeof limits;
type EffectTiming = ReturnType<Admission['selectRetention']>;
type BuildOptions = Parameters<typeof buildLocalPublicationPlan<Definition>>[0];
type EffectResults = BuildOptions['control'];
type ObservedEffect = Readonly<{wire: string}>;
type EffectObservationBody = Readonly<{data_policy_cid: string; captured_input_artifact_cids: string[]}>;
type EffectTimes = Readonly<{created_at: string; valid_until: string}>;
type Initialization = Readonly<{
  managedRun?: unknown; sourcePlan?: unknown; sourceHost?: unknown;
}>;
type OpenOptions = {
  moon: {
    clientProgramInstalledEffectManagedRunCheck?(run: unknown, prepared: unknown, original: unknown): unknown;
    clientProgramInstalledEffectManagedHostOpen?(run: unknown, owner: unknown, sources: readonly unknown[]): unknown;
  };
  facts: Readonly<{prepared: unknown; identity: unknown; owner: unknown}>;
  managedRun?: unknown;
};
type EffectMoon = AdmissionInput['moon'] & {
  clientProgramEffectDefinitionCid(prepared: unknown): string;
  clientProgramEffectCompilationResultNames(compiled: object): readonly string[];
  clientProgramEffectCompilationResultTransformation(compiled: object, prepared: unknown, result: number): unknown;
};
type EffectControl = AdmissionInput['control'] & EffectResults & {
  issueInstalledEffectInitialRetention(run: unknown, prepared: unknown, request: unknown,
    sourcePlan: unknown, policy: string, time: EffectTiming, bounds: EffectBounds): Definition;
};
type Acquired<Moon extends EffectMoon = EffectMoon, Control extends EffectControl = EffectControl> =
  ReturnType<typeof effectPublicationAdmission<Moon, Control, object>>;
type AdmissionWith<Moon extends EffectMoon, Control extends EffectControl> =
  Omit<AdmissionInput, 'moon' | 'control' | 'compilation'> & {moon: Moon; control: Control; compilation: object};
type ValueMoon = EffectMoon & {
  clientProgramIssueEffectSourceFreeInvocation(compilation: object, policy: string,
    bytes: number, nodes: number, depth: number): unknown;
};
type ValueControl = EffectControl & {
  admitRunEvidence(kind: 'observation_set', wire: string, bounds: EffectBounds): ObservedEffect;
  admit(kind: 'run_invocation', wire: string, bounds: EffectBounds): Definition;
};
type Issued = Readonly<{observation: ObservedEffect; invocation: unknown; owner: unknown}>;
type OriginalValueControl = EffectControl & {
  issueCheckedClientEffectSourceFreeInvocationOriginal(compiled: object, policy: string,
    bounds: EffectBounds): Issued & Readonly<{original: unknown}>;
};
type ContentMoon = EffectMoon & {clientProgramEffectAcquisitionCount(prepared: unknown): number};
type ContentControl = EffectControl & {
  issueCheckedClientSerializationInvocation(compiled: unknown, definition: Definition,
    generation: unknown, bounds: EffectBounds): Issued;
  issueCheckedInstalledEffectContentInvocation(run: unknown, prepared: unknown, request: unknown,
    sourcePlan: unknown, sourceHost: unknown, compilation: object, admission: unknown,
    definition: unknown, compiled: unknown, generation: unknown, bounds: EffectBounds): Issued;
  compiledSerializationPolicy(compiled: unknown): Readonly<{cid: string}> | undefined;
};
type ContentOptions = Initialization & {
  acquired: Acquired<ContentMoon, ContentControl>; compiled: unknown; generation: unknown;
};
type ModelMoon = EffectMoon & {clientProgramReleaseInferInvocationBinding(binding: unknown): boolean};
type ModelControl = EffectControl & {
  checkedClientEffectInferInvocation(prepared: unknown, compilation: object, definition: Definition,
    issued: unknown): Issued;
  bindCheckedInstalledEffectModelInvocation(run: unknown, prepared: unknown, request: unknown,
    sourcePlan: unknown, sourceHost: unknown, compilation: object, admission: unknown,
    definition: unknown, issued: unknown): Issued;
  compiledInferSourceFreeResultPolicy(compiled: unknown): unknown;
};
type ModelOptions<Bound extends Readonly<{binding: unknown}>> = Initialization & {
  acquired: Acquired<ModelMoon, ModelControl>;
  compiled: unknown;
  operation: {bindIssuedInvocation(control: ModelControl, input: Readonly<{
    compiled: unknown; runDefinition: Definition; issued: unknown;
  }>): Bound};
  issuance: unknown;
  modelEvidence: readonly unknown[];
  issuedModel?: Bound;
  modelOriginals?: readonly Readonly<{unit: number}>[];
};

// This is the existing admitted Effect Run, not a second preparation or a
// replacement timestamp. Common checks its exact Run/request correspondence.
export function openSourceFreeEffectComputation({moon, facts, managedRun}: OpenOptions) {
  if (managedRun === undefined ||
      typeof moon.clientProgramInstalledEffectManagedRunCheck !== 'function' ||
      typeof moon.clientProgramInstalledEffectManagedHostOpen !== 'function') {
    throw new Error('InstalledEffectPlanUnavailable');
  }
  checked(moon.clientProgramInstalledEffectManagedRunCheck(managedRun, facts.prepared, facts.identity));
  return checked(moon.clientProgramInstalledEffectManagedHostOpen(managedRun, facts.owner, []));
}

function finishSourceFreeEffectPublicationPlan(acquired: Acquired, observation: ObservedEffect,
  invocation: unknown, invocationOwner: unknown, sourceFreeInvocationOriginal?: unknown,
  managedRun?: unknown, sourcePlan?: unknown) {
  const {moon, control, prepared, compilation, admission, runDefinition,
    compiledPlan, dataPolicyCid, authorityScopeCid, namespaceId, storeAuthorityCid, now} = acquired;
  const run = JSON.parse(runDefinition.wire) as EffectTimes;
  const resultCount = moon.clientProgramEffectCompilationResultNames(
    compilation).length;
  const {plan, retention} = buildLocalPublicationPlan({control, admission, runDefinition,
    invocation, observation, compiledPlanCid: compiledPlan.identity,
    programDefinitionCid: moon.clientProgramEffectDefinitionCid(prepared),
    inputRelationCids: [], sourceEvidence: [], authorityScopeCid, namespaceId,
    storeAuthorityCid, dataPolicyCid, createdAt: run.created_at, now,
    resultCount, retainUntil: run.valid_until,
    moon, effectCompilation: compilation, preparedEffect: prepared,
    retentionSelection: acquired.selectRetention?.(),
    originalRetention: (managedRun === undefined ? undefined : control.issueInstalledEffectInitialRetention(managedRun, prepared,
      acquired.requestIdentity, sourcePlan, dataPolicyCid, acquired.selectRetention(), limits))});
  const result: typeof plan & {effectInputRetention: Definition; invocationOwner: unknown;
    localEvidenceContext: Readonly<{admission: unknown; runDefinition: Definition; runInvocation: unknown; observation: ObservedEffect}>;
    sourceFreeInvocationOriginal?: unknown} = {...plan, effectInputRetention: retention, invocationOwner,
    localEvidenceContext: Object.freeze({admission, runDefinition,
      runInvocation: invocation, observation})};
  if (sourceFreeInvocationOriginal !== undefined) result.sourceFreeInvocationOriginal = sourceFreeInvocationOriginal;
  return Object.freeze(result);
}

export function sourceFreeEffectPublicationPlan(options: AdmissionWith<ValueMoon, ValueControl>) {
  const acquired = effectPublicationAdmission(options);
  const {moon, control, compilation, dataPolicyCid} = acquired;
  const issued = checked(moon.clientProgramIssueEffectSourceFreeInvocation(
    compilation, dataPolicyCid, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
  const observation = control.admitRunEvidence('observation_set',
    moon.strategyRunEvidenceJson(runtimeField(issued, 0)), limits);
  const invocation = control.admit('run_invocation',
    moon.strategyPublicationContractJson(runtimeField(issued, 1)), limits);
  return finishSourceFreeEffectPublicationPlan(acquired, observation, invocation, runtimeField(issued, 1));
}

// The ordinary retained Request uses the exact early issuer receipt. It is
// attached once only after its actual managed Host/execution is retained.
export function sourceFreeEffectPublicationPlanOriginal(options: AdmissionWith<EffectMoon, OriginalValueControl> & Initialization) {
  const acquired = effectPublicationAdmission(options);
  const issued = acquired.control.issueCheckedClientEffectSourceFreeInvocationOriginal(
    acquired.compilation, acquired.dataPolicyCid, limits);
  return finishSourceFreeEffectPublicationPlan(acquired, issued.observation,
    issued.invocation, issued.owner, issued.original, options.managedRun, options.sourcePlan);
}

// The accepted Effect Run can be admitted before provider I/O, but its
// Observation Set cannot be issued until the exact acquired source exists.
export function acquiredEffectPublicationAdmission<Moon extends AdmissionInput['moon'],
  Control extends AdmissionInput['control'], Compilation>(
  options: Omit<AdmissionInput, 'moon' | 'control' | 'compilation'> & {moon: Moon; control: Control; compilation: Compilation},
) {
  return effectPublicationAdmission(options);
}

// Source-free Content is generated before its real Observation Set is issued.
// Use the original Common generation and explicit compiled policy, without a
// fabricated Source capture, Model call, input relation or second Run.
export function sourceFreeContentEffectPublicationPlan({acquired,compiled,generation,
  managedRun, sourcePlan, sourceHost}: ContentOptions) {
  const {moon,control,prepared,compilation,admission,runDefinition,compiledPlan,
    authorityScopeCid,namespaceId,storeAuthorityCid,now}=acquired;
  if(moon.clientProgramEffectAcquisitionCount(prepared)!==0)
    throw new TypeError('InvalidSourceFreeContentEffectPublication');
  const {observation,invocation,owner:invocationOwner}=
    managedRun === undefined
      ? control.issueCheckedClientSerializationInvocation(compiled,runDefinition,generation,limits)
      : control.issueCheckedInstalledEffectContentInvocation(managedRun, prepared, acquired.requestIdentity,
        sourcePlan, sourceHost, compilation, admission, acquired.definition, compiled, generation, limits);
  const policy=control.compiledSerializationPolicy(compiled);
  if(policy===undefined)throw new TypeError('ContentPolicyMissing');
  const run=JSON.parse(runDefinition.wire) as EffectTimes;
  const {plan,retention,retentionDependencies}=buildLocalPublicationPlan({control,admission,
    runDefinition,invocation,observation,compiledPlanCid:compiledPlan.identity,
    programDefinitionCid:moon.clientProgramEffectDefinitionCid(prepared),
    inputRelationCids:(JSON.parse(observation.wire) as EffectObservationBody).captured_input_artifact_cids,
    sourceEvidence:[],authorityScopeCid,namespaceId,storeAuthorityCid,dataPolicyCid:policy.cid,
    createdAt:run.created_at,now,retainUntil:run.valid_until,
    resultCount:moon.clientProgramEffectCompilationResultNames(compilation).length,
    moon,effectCompilation:compilation,preparedEffect:prepared,
    retentionSelection: acquired.selectRetention?.(),
    originalRetention: (managedRun === undefined ? undefined : control.issueInstalledEffectInitialRetention(managedRun, prepared,
      acquired.requestIdentity, sourcePlan, policy.cid, acquired.selectRetention(), limits))});
  const contentGenerations=Object.freeze([generation]);
  return Object.freeze({...plan,effectInputRetention:retention,invocationOwner,
    receiptEvidence:Object.freeze({...plan.receiptEvidence,contentGenerations}),
    captureEvidence:Object.freeze({...plan.captureEvidence,contentGenerations}),
    localEvidenceContext:Object.freeze({admission,runDefinition,runInvocation:invocation,observation,
      retentionDependencies,resultDataPolicy:policy,sourceFreeDependencyClosure:true})});
}

// A source-free Model still issues its real Observation Set after dispatch.
// Keep the original Effect admission and bind that exact Model issuer instead
// of issuing a no-external-work observation during Run preparation.
export function sourceFreeInferEffectPublicationPlan<Bound extends Readonly<{binding: unknown}>>({acquired,
  compiled, operation, issuance, modelEvidence, issuedModel, modelOriginals,
  managedRun, sourcePlan, sourceHost}: ModelOptions<Bound>) {
  const {moon, control, prepared, compilation, admission, runDefinition,
    compiledPlan, authorityScopeCid, namespaceId, storeAuthorityCid, now} = acquired;
  const issued = issuedModel ?? operation.bindIssuedInvocation(control, {
    compiled, runDefinition, issued: issuance});
  try {
    const {observation, invocation, owner: invocationOwner} =
      managedRun === undefined ? control.checkedClientEffectInferInvocation(prepared, compilation,
        runDefinition, issued) : control.bindCheckedInstalledEffectModelInvocation(managedRun,
        prepared, acquired.requestIdentity, sourcePlan, sourceHost, compilation, admission,
        acquired.definition, issued);
    const run = JSON.parse(runDefinition.wire) as EffectTimes;
    const {plan, retention, retentionDependencies} = buildLocalPublicationPlan({
      control, admission, runDefinition, invocation, observation,
      compiledPlanCid: compiledPlan.identity,
      programDefinitionCid: moon.clientProgramEffectDefinitionCid(prepared),
      inputRelationCids: (JSON.parse(observation.wire) as EffectObservationBody).captured_input_artifact_cids,
      sourceEvidence: [], modelEvidence,
      authorityScopeCid, namespaceId, storeAuthorityCid,
      dataPolicyCid: (JSON.parse(observation.wire) as EffectObservationBody).data_policy_cid,
      createdAt: run.created_at, now,
      resultCount: moon.clientProgramEffectCompilationResultNames(compilation).length,
      retainUntil: run.valid_until,
      moon, effectCompilation: compilation, preparedEffect: prepared,
      retentionSelection: acquired.selectRetention?.(),
    originalRetention: (managedRun === undefined ? undefined : control.issueInstalledEffectInitialRetention(managedRun, prepared,
      acquired.requestIdentity, sourcePlan, (JSON.parse(observation.wire) as EffectObservationBody).data_policy_cid, acquired.selectRetention(), limits))});
    return Object.freeze({...issued, plan: Object.freeze({...plan, effectInputRetention: retention,
      invocationOwner, localEvidenceContext: Object.freeze({admission,
        runDefinition, retentionDependencies: Object.freeze([...retentionDependencies,
          Object.freeze({kind: 'result_retention_policy',
            cid: retention.identity, wire: retention.wire})]),
        sourceFreeDependencyClosure:true,
        ...(modelOriginals === undefined ? {} : {
          modelOriginalByUnit: Object.freeze(Object.fromEntries(modelOriginals.map(model => [model.unit, model]))),
          modelRetention: retention,
        }),
        resultDataPolicy: control.compiledInferSourceFreeResultPolicy(compiled),
        runInvocation: invocation,
        observation})})});
  } catch (error) {
    if (issuedModel === undefined) moon.clientProgramReleaseInferInvocationBinding(issued.binding);
    throw error;
  }
}
