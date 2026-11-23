import {createHash, randomUUID} from 'node:crypto';
import {valuesExecutionContextCid} from './local-values-capacity.mjs';
import {checkedLocalOutputLimits} from './local-publication-limit-projection.mjs';
import {localContractLimits as limits} from './local-publication-limits.mjs';
import {
  prepareQueryInvocation, bindQueryInvocation, checkedOriginalQueryInvocation, cid, policyCid, instant,
} from './local-query-invocation.mjs';
import {localPublicationPlan, localRetentionTimes, retentionDependencies} from './local-publication-plan.mjs';

type InvocationChecks = Parameters<typeof checkedOriginalQueryInvocation>[1];
type QueryTimeControl = Parameters<typeof prepareQueryInvocation>[0];
type CompilationKind = Parameters<typeof checkedOriginalQueryInvocation>[4];
type Evidence = Readonly<{wire: string}>;
type Contract = Evidence & Readonly<{identity: string}>;
type CompiledRun = Readonly<{
  kind: CompilationKind; admission: unknown; compiledPlan: Contract;
  preparedEvidence: Evidence; authorization: Evidence;
}>;
type InvocationOriginal = Parameters<typeof checkedOriginalQueryInvocation>[0] & {
  compiled: CompiledRun; runDefinition: Contract; createdAt: string; validUntil: string;
};
type RetainedPlan = {
  executionOwner: Readonly<{program: unknown; compiled: CompiledRun}>;
  original: object;
  queryTimePreparation: unknown;
  queryTime: unknown;
  originalExplanation?: object;
};
type QueryTime = ReturnType<typeof bindQueryInvocation>;
type PublicationOriginal = Readonly<{
  kind: 'preparation' | 'installed_run'; value: unknown; authoringContext?: unknown;
}>;
type DefinitionTimes = {created_at?: string; valid_until?: string};
type PlanCaptureControl = {
  captureOriginalClientRunPlan(compiled: CompiledRun, original: unknown,
    definition: Contract, bounds: typeof limits, explanation?: unknown): object;
};
type AdmissionControl = QueryTimeControl & InvocationChecks & PlanCaptureControl & {
  prepareCheckedClientCompiledRun(prepared: unknown, kind: CompilationKind,
    policy: Readonly<{executionContextCid: string; hostPolicyCid: string; expiresAt: string; resultDataPolicy?: unknown}>,
    graph: unknown, original: unknown): CompiledRun;
  defineCheckedClientCompiledRun(compiled: CompiledRun, options: Readonly<{
    namespaceId: string; runId: string; createdAt: string; validUntil: string; retainedDefinitionWire?: string;
  }>): Contract;
};
type AdmissionOptions<Control extends AdmissionControl = AdmissionControl> = {
  control: Control;
  preparedProgram: unknown;
  authorityScopeCid: string;
  namespaceId: string;
  now(): string;
  retainedDefinitionWire?: string;
  requestIdentity?: unknown;
  compilationOriginal?: unknown;
  publicationPreparation?: unknown;
  publicationOriginal?: PublicationOriginal;
  invocationOriginal?: InvocationOriginal;
  originalExplanationPreparation?: unknown;
  inferGraph?: unknown;
  serializationGraph?: unknown;
  resultDataPolicy?: unknown;
};
type PublicationControl<Retention> = AdmissionControl & Parameters<typeof localPublicationPlan<Retention>>[0]['control'] & {
  issueCheckedClientCompiledInvocation(compiled: CompiledRun, definition: Contract,
    policy: Readonly<{dataPolicyCid: string}>, bounds: typeof limits, owner: unknown,
    prepared: unknown): Readonly<{observation: unknown; invocation: unknown}>;
  issueProgramInitialRetention(owner: unknown, prepared: unknown, request: unknown,
    policy: string, times: ReturnType<typeof localRetentionTimes>, contracts: typeof retentionDependencies,
    bounds: typeof limits): Retention;
};
type PublicationBindings = {
  clientProgramDefinitionCid(prepared: unknown): string;
  clientProgramResultCount(prepared: unknown): number;
  clientProgramPreparedLocalPublicationLimits(original: unknown, prepared: unknown, storeBytes: number): unknown;
  clientProgramInstalledManagedPublicationLimits(original: unknown, prepared: unknown, storeBytes: number): unknown;
};
type PublicationOptions<Retention> = AdmissionOptions<PublicationControl<Retention>> & {
  moon: PublicationBindings; storeAuthorityCid: string; publicationOriginal: PublicationOriginal;
};
type ProjectOutputLimits = (moon: PublicationBindings, prepared: unknown,
  original: PublicationOriginal) => ReturnType<typeof checkedLocalOutputLimits>;

const valuesAdmissions = new WeakMap<object, Readonly<{prepared: string; authorization: string}>>();
const originalPlans = new WeakMap<object, Readonly<RetainedPlan> | undefined>();
export function sourceFreePlanOriginal(plan: object) {return originalPlans.get(plan)?.original;}
export function sourceFreePlanExplanation(plan: object) {return originalPlans.get(plan)?.originalExplanation;}
export function sourceFreePlanExecutionOwner(plan: object) {return originalPlans.get(plan)?.executionOwner;}

function retainOriginalPlan<Plan extends Readonly<{runDefinition: Contract}>>(plan: Plan,
  compiled: CompiledRun, preparedProgram: unknown, control: PlanCaptureControl,
  queryTime: QueryTime | undefined, explanation: unknown): Plan {
  // Keep lifetime links in the existing private association, outside the
  // closed publication data bag. This replaces the larger timed Plan clone.
  const original = explanation === undefined
    ? control.captureOriginalClientRunPlan(compiled, preparedProgram, plan.runDefinition, limits)
    : control.captureOriginalClientRunPlan(compiled, preparedProgram, plan.runDefinition, limits, explanation);
  const retained: RetainedPlan = {
    executionOwner: Object.freeze({program: preparedProgram, compiled}),
    // Original admission uses the same metadata codec as its invocation and
    // publication. Later inspection keeps the reader's own explicit bounds.
    original,
    queryTimePreparation: queryTime?.queryTimePreparation,
    queryTime: queryTime?.queryTime,
  };
  if (explanation !== undefined) retained.originalExplanation = original;
  originalPlans.set(plan, Object.freeze(retained));
  return plan;
}
// The ordinary Effect-free INFER Host profile explicitly binds unknown
// provenance. It never relabels synthetic values or Model output as public.
// Effect-bearing profiles retain their separate required installation policy.
const inferResultPolicyWire = '{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}';
export const inferResultPolicy = Object.freeze({kind: 'data_policy', wire: inferResultPolicyWire,
  cid: `sha256:${createHash('sha256').update(inferResultPolicyWire).digest('hex')}`});

// Preserve the closed publication-plan shape. The request journal retains
// this original configuration with the admission it actually authorized.
export function sourceFreeValuesAdmissionEvidence(plan: object) {
  return valuesAdmissions.get(plan);
}
export function sourceFreeValuesPlan<Retention>({moon, control, preparedProgram,
  authorityScopeCid, namespaceId, storeAuthorityCid, now,
  retainedDefinitionWire, requestIdentity, publicationOriginal, compilationOriginal, publicationPreparation, invocationOriginal, originalExplanationPreparation}: PublicationOptions<Retention>) {
  const original = invocationOriginal === undefined ? undefined : checkedOriginalQueryInvocation(
    invocationOriginal, control, preparedProgram, requestIdentity, 'values', retainedDefinitionWire);
  const at = original === undefined ? Date.parse(now()) : undefined;
  if (original === undefined && !Number.isFinite(at)) throw new TypeError('InvalidLocalClock');
  const retained = retainedDefinitionWire === undefined ? undefined :
    JSON.parse(retainedDefinitionWire) as DefinitionTimes | null;
  const queryInvocation=original === undefined && publicationPreparation === undefined
    ? prepareQueryInvocation(control,preparedProgram,requestIdentity,retained) : undefined;
  const createdAt = original?.createdAt ?? retained?.created_at ?? queryInvocation?.createdAt ?? instant(at!);
  const validUntil = original?.validUntil ?? retained?.valid_until ??
    instant(at! + 24 * 60 * 60 * 1000);
  // The original checked plan and installed publication owner enforce row,
  // cell and byte demand. Authored/output counts are not a new Host profile.
  const hostPolicyCid = policyCid('source-free-values');
  const contextCid = valuesExecutionContextCid(authorityScopeCid);
  const compiled = original?.compiled ?? control.prepareCheckedClientCompiledRun(preparedProgram,
    'values', {executionContextCid: contextCid,
      hostPolicyCid, expiresAt: validUntil}, undefined, compilationOriginal);
  const {admission, compiledPlan} = compiled;
  const runDefinition = original?.runDefinition ?? control.defineCheckedClientCompiledRun(compiled, {
    namespaceId, runId: randomUUID(), createdAt, validUntil,
    retainedDefinitionWire,
  });
  const queryTime=original === undefined
    ? bindQueryInvocation(control,queryInvocation,preparedProgram,compiled,runDefinition)
    : {queryTimePreparation:original.queryTimePreparation,queryTime:original.queryTime};
  const dataPolicyCid = policyCid('local-result-data');
  const {observation, invocation} = control.issueCheckedClientCompiledInvocation(
    compiled, runDefinition, {dataPolicyCid}, limits, publicationPreparation, preparedProgram);
  if ((publicationPreparation !== undefined || publicationOriginal?.kind === 'installed_run') &&
      (publicationOriginal?.kind !== 'installed_run' || publicationPreparation === undefined ||
        publicationPreparation !== publicationOriginal.value)) {
    throw new TypeError('OriginalProgramRetentionOwnerRequired');
  }
  const originalRetention = publicationOriginal?.kind !== 'installed_run' ? undefined :
    control.issueProgramInitialRetention(publicationPreparation, preparedProgram, requestIdentity, dataPolicyCid,
      localRetentionTimes(now), retentionDependencies, limits);
  const plan = localPublicationPlan({control, originalRetention, admission, runDefinition, invocation,
    observation, compiledPlanCid: compiledPlan.identity,
    programDefinitionCid: moon.clientProgramDefinitionCid(preparedProgram),
    inputRelationCids: [], sourceEvidence: [], authorityScopeCid,
    namespaceId, storeAuthorityCid, dataPolicyCid, createdAt,
    now, resultCount: moon.clientProgramResultCount(preparedProgram),
    compiled, preparedProgram, publicationOriginal,
    // The existing Result owner retains one row index per unsorted row.
    // Consume the common checked Result envelope and publication policy;
    // the adapter does not infer workspace or field bounds from output rows.
    outputLimits: (checkedLocalOutputLimits as ProjectOutputLimits)(moon, preparedProgram, publicationOriginal),
  });
  valuesAdmissions.set(plan, Object.freeze({
    prepared: compiled.preparedEvidence.wire,
    authorization: compiled.authorization.wire,
  }));
  return retainOriginalPlan(plan, compiled, preparedProgram, control, queryTime, originalExplanationPreparation);
}

// Admit the complete checked task graph, including acquired sources, to the
// same portable Run owner used by the installed source-free profile. Physical
// acquisition and Source Evidence must still be established before this Run
// can be published; this admission alone never authorizes provider I/O.
export function acquiredTaskRunAdmission(options: AdmissionOptions) {
  return checkedTaskRunAdmission(options, 'tasks');
}

export function checkedTaskRunAdmission({control, preparedProgram, inferGraph, serializationGraph,
  authorityScopeCid, namespaceId, now, retainedDefinitionWire, resultDataPolicy, requestIdentity, compilationOriginal, publicationPreparation, invocationOriginal, publicationOriginal, originalExplanationPreparation}: AdmissionOptions, kind: Exclude<CompilationKind, 'values'>) {
  const original = invocationOriginal === undefined ? undefined : checkedOriginalQueryInvocation(
    invocationOriginal, control, preparedProgram, requestIdentity, kind, retainedDefinitionWire);
  const at = original === undefined ? Date.parse(now()) : undefined;
  if (original === undefined && !Number.isFinite(at)) throw new TypeError('InvalidLocalClock');
  const retained = retainedDefinitionWire === undefined ? undefined :
    JSON.parse(retainedDefinitionWire) as DefinitionTimes | null;
  const queryInvocation=original === undefined && !(kind === 'tasks' && publicationPreparation !== undefined)
    ? prepareQueryInvocation(control,preparedProgram,requestIdentity,retained) : undefined;
  const createdAt = original?.createdAt ?? retained?.created_at ?? queryInvocation?.createdAt ?? instant(at!);
  const validUntil = original?.validUntil ?? retained?.valid_until ??
    instant(at! + 24 * 60 * 60 * 1000);
  const contextCid = cid({version: 'actql-installed-local-context/0.1',
    authority_scope_cid: authorityScopeCid});
  const compiled = original?.compiled ?? control.prepareCheckedClientCompiledRun(preparedProgram,
    kind, {executionContextCid: contextCid,
      hostPolicyCid: policyCid(kind === 'infer' ? 'checked-infer'
        : kind === 'serialization' ? 'checked-content' : 'checked-tasks'),
      expiresAt: validUntil,
      ...(kind === 'infer' ? {resultDataPolicy: resultDataPolicy ?? inferResultPolicy} : {})},
    kind === 'serialization' ? serializationGraph : inferGraph, compilationOriginal);
  const {admission, compiledPlan} = compiled;
  const runDefinition = original?.runDefinition ?? control.defineCheckedClientCompiledRun(compiled, {
    namespaceId, runId: randomUUID(), createdAt, validUntil,
    retainedDefinitionWire,
  });
  const queryTime=original === undefined
    ? bindQueryInvocation(control,queryInvocation,preparedProgram,compiled,runDefinition)
    : {queryTimePreparation:original.queryTimePreparation,queryTime:original.queryTime};
  const admitted = Object.freeze({...compiled, compiled, runDefinition, createdAt, publicationPreparation, requestIdentity,
    authoringContextOriginal: publicationOriginal?.authoringContext,
    ...queryTime,
    ...(kind === 'infer' ? {inferGraph} : {}),
    ...(kind === 'serialization' ? {serializationGraph} : {})});
  return kind === 'tasks' ? retainOriginalPlan(admitted, compiled, preparedProgram, control, queryTime, originalExplanationPreparation) : admitted;
}

// Multi-task source-free Programs use the common task compiler and the same
// empty initial input set. No source observation is invented for Values roots.
export function sourceFreeTaskPlan<Retention>(options: PublicationOptions<Retention>) {
  const acquired = acquiredTaskRunAdmission(options);
  const {moon, control, preparedProgram, authorityScopeCid, namespaceId,
    storeAuthorityCid, now, publicationOriginal, publicationPreparation} = options;
  const dataPolicyCid = policyCid('local-result-data');
  const {observation, invocation} = control.issueCheckedClientCompiledInvocation(
    acquired.compiled, acquired.runDefinition, {dataPolicyCid}, limits,
    publicationPreparation, preparedProgram);
  if ((publicationPreparation !== undefined || publicationOriginal?.kind === 'installed_run') &&
      (publicationOriginal?.kind !== 'installed_run' || publicationPreparation === undefined ||
        publicationPreparation !== publicationOriginal.value)) {
    throw new TypeError('OriginalProgramRetentionOwnerRequired');
  }
  const originalRetention = publicationOriginal?.kind !== 'installed_run' ? undefined :
    control.issueProgramInitialRetention(publicationPreparation, preparedProgram, acquired.requestIdentity, dataPolicyCid,
      localRetentionTimes(now), retentionDependencies, limits);
  const plan = localPublicationPlan({control, originalRetention, admission: acquired.admission,
    runDefinition: acquired.runDefinition, invocation, observation,
    compiledPlanCid: acquired.compiledPlan.identity,
    programDefinitionCid: moon.clientProgramDefinitionCid(preparedProgram),
    inputRelationCids: [], sourceEvidence: [], authorityScopeCid, namespaceId,
    storeAuthorityCid, dataPolicyCid, createdAt: acquired.createdAt, now,
    resultCount: moon.clientProgramResultCount(preparedProgram),
    compiled: acquired.compiled, preparedProgram, publicationOriginal,
    outputLimits: (checkedLocalOutputLimits as ProjectOutputLimits)(moon, preparedProgram, publicationOriginal)});
  valuesAdmissions.set(plan, Object.freeze({prepared: acquired.preparedEvidence.wire,
    authorization: acquired.authorization.wire}));
  originalPlans.set(plan, originalPlans.get(acquired));
  return plan;
}
