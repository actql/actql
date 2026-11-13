// Bind the installed source-free compiler to the common Run and publication
// owner. Physical Local policy CIDs are stable identities of this Host profile.
import {runtimeField, runtimeOptionalField} from '../host-common/compiler-binding.generated.mjs';
import {createHash, randomUUID} from 'node:crypto';
import {checked} from '../host-common/runtime-result.mjs';
import {valuesExecutionContextCid} from './local-values-capacity.mjs';
import {resultOutputLimitFields} from '../host-common/result-output-limits.mjs';
import {hostResultStorePolicy} from './host-result-service-recipe.cjs';
import {sampleOriginalQueryTime} from './query-evaluation-clock.mjs';
import {withOriginalInferModelObservation} from './infer-effect-observation.mjs';

function prepareQueryInvocation(control, prepared, request, retained) {
  if (control.clientRequiresQueryTime?.(prepared) !== true) return undefined;
  if (request === undefined) throw new TypeError('OriginalClientQueryRequestRequired');
  if (retained !== undefined) return {request};
  const createdAt=sampleOriginalQueryTime();
  return {request,createdAt,preparation:control.prepareClientQueryTime(prepared,request,createdAt)};
}

function bindQueryInvocation(control, original, prepared, compiled, definition) {
  if (original === undefined) return {};
  if (original.preparation === undefined) {
    return control.restoreClientQueryTime(prepared,compiled,definition,original.request);
  }
  return Object.freeze({queryTimePreparation:original.preparation,
    queryTime:control.bindClientQueryTime(original.preparation,prepared,compiled,definition,original.request)});
}

// Called only by the existing timed Request adoption constructor. Its parent
// already retains the compiler artifact; the returned Option is a Core original.
export function prepareTimedClientInvocation({control, preparedProgram, requestIdentity,
  compilationOriginal, kind, authorityScopeCid, namespaceId, now, retainedDefinitionWire, retainedInvocation}) {
  if (!['values', 'tasks'].includes(kind) || compilationOriginal === undefined || requestIdentity === undefined ||
      retainedInvocation === null || typeof retainedInvocation !== 'object' || Object.isFrozen(retainedInvocation)) {
    throw new TypeError('OriginalClientQueryInvocationRequired');
  }
  const fields = Object.getOwnPropertyDescriptors(retainedInvocation);
  if (fields.preparedProgram?.value !== preparedProgram || fields.requestIdentity?.value !== requestIdentity ||
      ['compiled', 'runDefinition', 'createdAt', 'validUntil', 'queryTimePreparation', 'queryTime']
        .some(name => fields[name]?.writable !== true || !Object.hasOwn(fields[name] ?? {}, 'value') ||
          fields[name].value !== undefined)) throw new TypeError('OriginalClientQueryInvocationRequired');
  // Existing native Definition admission permits at most100000 wire bytes.
  // Fence the earlier JS parse too; this cannot admit a looser native body.
  if (retainedDefinitionWire !== undefined &&
      (typeof retainedDefinitionWire !== 'string' || retainedDefinitionWire.length > 100000)) {
    throw new TypeError('OriginalClientQueryInvocationRequired');
  }
  const at = Date.parse(now());
  if (!Number.isFinite(at)) throw new TypeError('InvalidLocalClock');
  const retained = retainedDefinitionWire === undefined ? undefined : JSON.parse(retainedDefinitionWire);
  const queryInvocation = retained === undefined
    ? {request: requestIdentity, createdAt: sampleOriginalQueryTime(), preparation: undefined}
    : {request: requestIdentity};
  if (retained === undefined) {
    retainedInvocation.createdAt = queryInvocation.createdAt;
    retainedInvocation.queryTimePreparation = queryInvocation.preparation = control.prepareClientQueryTime(
      preparedProgram, requestIdentity, queryInvocation.createdAt);
  }
  const createdAt = retainedInvocation.createdAt = retained?.created_at ?? queryInvocation.createdAt;
  const validUntil = retainedInvocation.validUntil = retained?.valid_until ?? instant(at + 24 * 60 * 60 * 1000);
  const contextCid = kind === 'values' ? valuesExecutionContextCid(authorityScopeCid)
    : cid({version: 'actql-installed-local-context/0.1', authority_scope_cid: authorityScopeCid});
  const compiled = retainedInvocation.compiled = control.prepareCheckedClientCompiledRun(preparedProgram, kind,
    {executionContextCid: contextCid,
      hostPolicyCid: policyCid(kind === 'values' ? 'source-free-values' : 'checked-tasks'),
      expiresAt: validUntil}, undefined, compilationOriginal);
  const runDefinition = retainedInvocation.runDefinition = control.defineCheckedClientCompiledRun(compiled,
    {namespaceId, runId: randomUUID(), createdAt, validUntil, retainedDefinitionWire});
  const queryTime = bindQueryInvocation(control, queryInvocation, preparedProgram, compiled, runDefinition);
  retainedInvocation.queryTimePreparation = queryTime.queryTimePreparation;
  retainedInvocation.queryTime = queryTime.queryTime;
  const invocationOriginal = control.clientQueryTimeInvocationOriginal(queryTime.queryTimePreparation, preparedProgram);
  Object.freeze(retainedInvocation);
  return Object.freeze({original: invocationOriginal, retained: retainedInvocation});
}

function checkedOriginalQueryInvocation(original, control, prepared, request, kind, retainedWire) {
  if (original.preparedProgram !== prepared || original.requestIdentity !== request ||
      original.compiled?.kind !== kind || original.queryTimePreparation === undefined ||
      original.queryTime === undefined || retainedWire !== undefined &&
        original.runDefinition?.wire !== retainedWire) {
    throw new TypeError('ForeignClientQueryInvocationOriginal');
  }
  control.checkClientCompiledRunOwner(original.compiled, prepared);
  control.checkClientCompiledRunDefinition(original.compiled, original.runDefinition);
  return original;
}

// Contract and evidence issuance bounds only. Captured Named Result snapshots
// consume the same original logical output policy as durable publication,
// including its relation wrapper; these metadata bounds do not cap row data.
const limits = Object.freeze({maxWireBytes: 1000000, maxNodes: 100000,
  maxDepth: 64});
export const localOutputLimits = Object.freeze({
  maxResultFields: 10, maxResultMappingWork: 1000,
  maxResultOrderWork: 10000, maxResultWorkspaceEntries: 100,
  maxRows: 10000, maxValueNodes: 1000000, maxValueTextBytes: 10000000,
  maxValueDepth: 64, maxValueWork: 1000000, maxWireBytes: 10000000,
  maxWireNodes: 1000000, maxWireDepth: 64, maxColumns: 100,
  maxOrderWork: 1000000, maxLogicalWireBytes: 10000000,
  maxLogicalWireNodes: 1000003, maxLogicalWireDepth: 66,
  maxSchemaFields: 100, maxSchemaBytes: 100000,
  maxSchemaNodes: 10000, maxSchemaDepth: 64, maxBatchBytes: 65536,
});
// Project the common checked policy; no adapter-specific row/field formula.
export function checkedLocalOutputLimits(moon, preparedProgram, publicationOriginal) {
  let values;
  if (publicationOriginal?.kind === 'preparation') {
    values = moon.clientProgramPreparedLocalPublicationLimits(publicationOriginal.value,
      preparedProgram, hostResultStorePolicy.maxObjectBytes);
  } else if (publicationOriginal?.kind === 'installed_run') {
    values = moon.clientProgramInstalledManagedPublicationLimits(publicationOriginal.value,
      preparedProgram, hostResultStorePolicy.maxObjectBytes);
  } else {
    throw new TypeError('InvalidCheckedLocalPublicationOriginal');
  }
  const names = resultOutputLimitFields;
  if (!Array.isArray(values) || values.length !== names.length ||
      values.some(value => !Number.isSafeInteger(value) || value < 0)) {
    throw new TypeError('InvalidCheckedLocalPublicationLimits');
  }
  return Object.freeze(Object.fromEntries(names.map((name,index) => [name,values[index]])));
}
export const localContractLimits = limits;

const cid = value => `sha256:${createHash('sha256')
  .update(JSON.stringify(value)).digest('hex')}`;
const policyCid = name => cid({version: 'actql-installed-local-policy/0.1',
  name});
const valuesAdmissions = new WeakMap();
const originalPlans = new WeakMap();
export function sourceFreePlanOriginal(plan) {return originalPlans.get(plan)?.original;}
export function sourceFreePlanExecutionOwner(plan) {return originalPlans.get(plan)?.executionOwner;}

function retainOriginalPlan(plan, compiled, preparedProgram, control, queryTime) {
  // Keep lifetime links in the existing private association, outside the
  // closed publication data bag. This replaces the larger timed Plan clone.
  originalPlans.set(plan, Object.freeze({
    executionOwner: Object.freeze({program: preparedProgram, compiled}),
    // Original admission uses the same metadata codec as its invocation and
    // publication. Later inspection keeps the reader's own explicit bounds.
    original: control.captureOriginalClientRunPlan(
      compiled, preparedProgram, plan.runDefinition, limits),
    queryTimePreparation: queryTime?.queryTimePreparation,
    queryTime: queryTime?.queryTime,
  }));
  return plan;
}
// The ordinary Effect-free INFER Host profile explicitly binds unknown
// provenance. It never relabels synthetic values or Model output as public.
// Effect-bearing profiles retain their separate required installation policy.
const inferResultPolicyWire = '{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}';
const inferResultPolicy = Object.freeze({kind: 'data_policy', wire: inferResultPolicyWire,
  cid: `sha256:${createHash('sha256').update(inferResultPolicyWire).digest('hex')}`});

// Preserve the closed publication-plan shape. The request journal retains
// this original configuration with the admission it actually authorized.
export function sourceFreeValuesAdmissionEvidence(plan) {
  return valuesAdmissions.get(plan);
}
const instant = value => new Date(value).toISOString();

// These retained contract bodies use canonical key order. Previously only
// opaque profile IDs were emitted; durable dependency recovery needs the
// exact canonical body as well. This is a coordinated 0.1 identity change,
// not a decoder for the former noncanonical profile hash.
const retentionDependencies = Object.freeze([
  ['retention_contract', 'local-result-retention'],
  ['metadata_retention_policy', 'local-result-metadata'],
  ['clock_contract', 'local-clock'],
].map(([kind, name]) => {
  const body = {name, version: 'actql-installed-local-policy/0.1'};
  return Object.freeze({kind, cid: cid(body), wire: JSON.stringify(body)});
}));

function localPublicationPlan(options) {
  return buildLocalPublicationPlan(options).plan;
}

// The same installed Host retention clocks feed early input custody and
// final publication. This DATA resolves no permission or additional lifetime.
function localRetentionTimes(now, retainUntil) {
  const at = Date.parse(now());
  const availableAt = retainUntil === undefined ? at + 60 * 60 * 1000
    : Math.max(at + 60 * 60 * 1000, Date.parse(retainUntil));
  return Object.freeze({availableUntil: instant(availableAt),
    deleteBy: instant(availableAt + 60 * 60 * 1000),
    metadataDeleteBy: instant(Math.max(at + 7 * 24 * 60 * 60 * 1000,
      availableAt + 2 * 60 * 60 * 1000))});
}

export function keyedInputRetentionSelection(acquired) {
  return acquired.selectRetention();
}

function issueLocalResultRetention(control, dataPolicyCid, selection) {
  const {availableUntil, deleteBy, metadataDeleteBy} = selection;
  return control.seal('result_retention_policy', JSON.stringify({
    version: 'actql-result-retention-policy/0.1',
    retention_contract_cid: retentionDependencies[0].cid,
    effective_data_policy_cid: dataPolicyCid,
    available_until: availableUntil, delete_by: deleteBy,
    extension_ceiling_at: metadataDeleteBy,
    metadata_retention_policy_cid: retentionDependencies[1].cid,
    metadata_delete_by: metadataDeleteBy,
    clock_contract_cid: retentionDependencies[2].cid,
  }), limits);
}

// Keep the retained input policy available to Effect evidence issuance
// without extending the closed publication-plan JS bridge used by ordinary Runs.
function buildLocalPublicationPlan({control, admission, runDefinition, invocation,
  observation, compiledPlanCid, programDefinitionCid, inputRelationCids,
  sourceEvidence, authorityScopeCid, namespaceId, storeAuthorityCid,
  dataPolicyCid, createdAt, now, resultCount, retainUntil,
  compiled, preparedProgram, effectCompilation, preparedEffect, moon,
  modelEvidence = [], outputLimits = localOutputLimits, retentionSelection, originalRetention}) {
  const {availableUntil, deleteBy, metadataDeleteBy} = retentionSelection ?? localRetentionTimes(now, retainUntil);
  const retention = originalRetention ?? issueLocalResultRetention(control, dataPolicyCid,
    {availableUntil, deleteBy, metadataDeleteBy});
  const normalizationJournal = control.sealRunEvidence(
    'normalization_journal', JSON.stringify({
      version: 'actql-normalization-journal/0.1',
      rule_catalog_cid: policyCid('local-normalization'), entries: [],
    }), limits);
  const authoringContext = control.sealRunEvidence('authoring_context',
    JSON.stringify({version: 'actql-authoring-context/0.1',
      program_definition_cid: programDefinitionCid,
      annotations: []}), limits);
  const plan = Object.freeze({admission, runDefinition, invocation, observation,
    normalizationJournal, authoringContext,
    results: Object.freeze(Array.from({length: resultCount}, (_, index) => {
      const transformation = effectCompilation !== undefined ? checked(
        moon.clientProgramEffectCompilationResultTransformation(
          effectCompilation, preparedEffect, index)) :
        compiled === undefined ? undefined :
          control.compiledRunResultTransformation(compiled, preparedProgram, index);
      return Object.freeze({retention,
        ...(transformation == null ? {} : {transformation}),
        evidenceContext: Object.freeze({
        computationContractCid: compiledPlanCid,
        inputRelationCids, scopeCid: runDefinition.identity,
        effectiveDataPolicyCid: dataPolicyCid, authorityScopeCid,
      })});
    })),
    receiptEvidence: Object.freeze({bindings: [], sourceEvidence,
      modelEvidence: Object.freeze([...modelEvidence]), barrierAttemptReceiptCids: []}),
    captureEvidence: Object.freeze({pendingSourceStateAdvances: [],
      modelEvidence: Object.freeze([...modelEvidence])}),
    request: Object.freeze({namespaceId, authorityScopeCid,
      publicationPolicyCid: policyCid('local-publication'),
      publicationTargetCid: storeAuthorityCid, requestedAt: createdAt}),
    attempt: Object.freeze({attemptId: randomUUID(),
      fenceCid: cid({version: 'actql-local-run-fence/0.1',
        run_definition_cid: runDefinition.identity}),
      externalIdempotencyKey: undefined, startedAt: createdAt}),
    outputLimits, contractLimits: limits, now,
  });
  return {plan, retention, retentionDependencies};
}

// The Effect Run acceptance owner already compiled and admitted this Run.
// Reuse its exact compiler outputs; do not prepare or compile another Program
// to reconstruct publication evidence. Captured inputs must outlive approval
// waiting, so retention covers the admitted Run's validity window.
function effectPublicationAdmission({moon, control, prepared,
  compilation, allowed, definition, authorityScopeCid, namespaceId,
  storeAuthorityCid, now, resultDataPolicy, queryTimePreparation, queryTime, identity}) {
  const template = control.admitRunEvidence('bound_invocation_template',
    moon.clientProgramEffectCompilationTemplateWire(compilation), limits);
  const preparedEvidence = control.admitRunEvidence('prepared_invocation',
    moon.strategyRunEvidenceJson(
      moon.clientProgramAllowedEffectRunPrepared(allowed)), limits);
  const authorization = control.admitRunEvidence('run_authorization',
    moon.strategyRunEvidenceJson(
      moon.clientProgramAllowedEffectRunAuthorization(allowed)), limits);
  const compiledPlan = control.admit('compiled_plan',
    moon.clientProgramEffectCompilationCompiledPlanWire(compilation), limits);
  const admission = control.admitCheckedClientEffectRunPublication(prepared,
    template, preparedEvidence, authorization, compiledPlan);
  const runDefinition = control.admit('run_definition',
    moon.strategyPublicationContractJson(definition), limits);
  const dataPolicyCid = policyCid('local-result-data');
  // Retention is immutable Run DATA, selected at its original first-use
  // boundary and reused after Model awaits. Keep the live permission/current
  // clock below unchanged; this selection never grants or extends access.
  let retentionSelection, retentionFailure, retentionFailed = false;
  const selectRetention = () => {
    if (retentionFailed) throw retentionFailure;
    if (retentionSelection !== undefined) return retentionSelection;
    try {
      const run = JSON.parse(runDefinition.wire);
      retentionSelection = Object.freeze({...localRetentionTimes(now, run.valid_until),
        expiresAt: run.valid_until,
        retentionContractCid: retentionDependencies[0].cid,
        metadataRetentionPolicyCid: retentionDependencies[1].cid,
        clockContractCid: retentionDependencies[2].cid});
      return retentionSelection;
    } catch (cause) {
      retentionFailed = true; retentionFailure = cause; throw cause;
    }
  };
  return Object.freeze({moon, control, prepared, compilation, allowed,
    definition, authorityScopeCid, namespaceId, storeAuthorityCid, now, selectRetention,
    admission, runDefinition, compiledPlan, dataPolicyCid, resultDataPolicy,
    queryTimePreparation, queryTime, requestIdentity: identity,
    resultDataPolicyLimits: limits});
}

// This is the existing admitted Effect Run, not a second preparation or a
// replacement timestamp. Common checks its exact Run/request correspondence.
export function openSourceFreeEffectComputation({moon, facts, managedRun}) {
  if (managedRun === undefined ||
      typeof moon.clientProgramInstalledEffectManagedRunCheck !== 'function' ||
      typeof moon.clientProgramInstalledEffectManagedHostOpen !== 'function') {
    throw new Error('InstalledEffectPlanUnavailable');
  }
  checked(moon.clientProgramInstalledEffectManagedRunCheck(managedRun, facts.prepared, facts.identity));
  return checked(moon.clientProgramInstalledEffectManagedHostOpen(managedRun, facts.owner, []));
}

export function sourceFreeEffectPublicationPlan(options) {
  const acquired = effectPublicationAdmission(options);
  const {moon, control, prepared, compilation, admission, runDefinition,
    compiledPlan, dataPolicyCid, authorityScopeCid, namespaceId,
    storeAuthorityCid, now} = acquired;
  const sourceFree = checked(moon.clientProgramIssueEffectSourceFreeInvocation(
    compilation, dataPolicyCid, limits.maxWireBytes, limits.maxNodes,
    limits.maxDepth));
  const observation = control.admitRunEvidence('observation_set',
    moon.strategyRunEvidenceJson(runtimeField(sourceFree, 0)), limits);
  const invocation = control.admit('run_invocation',
    moon.strategyPublicationContractJson(runtimeField(sourceFree, 1)), limits);
  const run = JSON.parse(runDefinition.wire);
  const resultCount = moon.clientProgramEffectCompilationResultNames(
    compilation).length;
  const {plan, retention} = buildLocalPublicationPlan({control, admission, runDefinition,
    invocation, observation, compiledPlanCid: compiledPlan.identity,
    programDefinitionCid: moon.clientProgramEffectDefinitionCid(prepared),
    inputRelationCids: [], sourceEvidence: [], authorityScopeCid, namespaceId,
    storeAuthorityCid, dataPolicyCid, createdAt: run.created_at, now,
    resultCount, retainUntil: run.valid_until,
    moon, effectCompilation: compilation, preparedEffect: prepared,
    retentionSelection: acquired.selectRetention?.()});
  return Object.freeze({...plan, effectInputRetention: retention, invocationOwner: runtimeField(sourceFree, 1),
    localEvidenceContext: Object.freeze({admission, runDefinition,
      runInvocation: invocation, observation})});
}

// The accepted Effect Run can be admitted before provider I/O, but its
// Observation Set cannot be issued until the exact acquired source exists.
export function acquiredEffectPublicationAdmission(options) {
  return effectPublicationAdmission(options);
}

// Source-free Content is generated before its real Observation Set is issued.
// Use the original Common generation and explicit compiled policy, without a
// fabricated Source capture, Model call, input relation or second Run.
export function sourceFreeContentEffectPublicationPlan({acquired,compiled,generation}) {
  const {moon,control,prepared,compilation,admission,runDefinition,compiledPlan,
    authorityScopeCid,namespaceId,storeAuthorityCid,now}=acquired;
  if(moon.clientProgramEffectAcquisitionCount(prepared)!==0)
    throw new TypeError('InvalidSourceFreeContentEffectPublication');
  const {observation,invocation,owner:invocationOwner}=
    control.issueCheckedClientSerializationInvocation(compiled,runDefinition,generation,limits);
  const policy=control.compiledSerializationPolicy(compiled);
  if(policy===undefined)throw new TypeError('ContentPolicyMissing');
  const run=JSON.parse(runDefinition.wire);
  const {plan,retention,retentionDependencies}=buildLocalPublicationPlan({control,admission,
    runDefinition,invocation,observation,compiledPlanCid:compiledPlan.identity,
    programDefinitionCid:moon.clientProgramEffectDefinitionCid(prepared),
    inputRelationCids:JSON.parse(observation.wire).captured_input_artifact_cids,
    sourceEvidence:[],authorityScopeCid,namespaceId,storeAuthorityCid,dataPolicyCid:policy.cid,
    createdAt:run.created_at,now,retainUntil:run.valid_until,
    resultCount:moon.clientProgramEffectCompilationResultNames(compilation).length,
    moon,effectCompilation:compilation,preparedEffect:prepared,
    retentionSelection: acquired.selectRetention?.()});
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
export function sourceFreeInferEffectPublicationPlan({acquired,
  compiled, operation, issuance, modelEvidence, issuedModel, modelOriginals}) {
  const {moon, control, prepared, compilation, admission, runDefinition,
    compiledPlan, authorityScopeCid, namespaceId, storeAuthorityCid, now} = acquired;
  const issued = issuedModel ?? operation.bindIssuedInvocation(control, {
    compiled, runDefinition, issued: issuance});
  try {
    const {observation, invocation, owner: invocationOwner} =
      control.checkedClientEffectInferInvocation(prepared, compilation,
        runDefinition, issued);
    const run = JSON.parse(runDefinition.wire);
    const {plan, retention, retentionDependencies} = buildLocalPublicationPlan({
      control, admission, runDefinition, invocation, observation,
      compiledPlanCid: compiledPlan.identity,
      programDefinitionCid: moon.clientProgramEffectDefinitionCid(prepared),
      inputRelationCids: JSON.parse(observation.wire).captured_input_artifact_cids,
      sourceEvidence: [], modelEvidence,
      authorityScopeCid, namespaceId, storeAuthorityCid,
      dataPolicyCid: JSON.parse(observation.wire).data_policy_cid,
      createdAt: run.created_at, now,
      resultCount: moon.clientProgramEffectCompilationResultNames(compilation).length,
      retainUntil: run.valid_until,
      moon, effectCompilation: compilation, preparedEffect: prepared,
      retentionSelection: acquired.selectRetention?.()});
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

export function acquiredEffectPublicationPlan({acquired, captured,
  sourceEvidence: originalSourceEvidence, sourceEvidenceWire,
  captureStartedAt, captureCompletedAt, content, sourcePlan}) {
  if (content === undefined && captured?.inputKind === 'whole-input') {
    return acquiredMultiEffectPublicationPlan({acquired,
      sources: [{captured, sourceEvidence: originalSourceEvidence, sourceEvidenceWire}],
      captureStartedAt, captureCompletedAt, sourcePlan});
  }
  const {moon, control, prepared, compilation, definition, admission,
    runDefinition, compiledPlan, authorityScopeCid,
    namespaceId, storeAuthorityCid, now} = acquired;
  if (typeof sourceEvidenceWire !== 'string' ||
      typeof captureStartedAt !== 'string' ||
      typeof captureCompletedAt !== 'string' ||
      captured?.logicalInput === undefined ||
      captured?.checkedSource === undefined ||
      captured?.identity === undefined ||
      captured?.requirement === undefined ||
      captured?.capture === undefined ||
      moon.clientProgramEffectCapturedSourceMatches(prepared,
        captured.capture.source()) !== true) {
    throw new TypeError('InvalidAcquiredEffectPublication');
  }
  const source = captured.checkedSource;
  const {observation, invocation, owner: invocationOwner} =
    content === undefined ? control.issueCheckedClientEffectCapturedInvocation(
      prepared, compilation, admission, definition,
      captured.capture.source(), {sourceEvidenceWire,
        inputLogicalWire: moon.strategyRunEvidenceJson(captured.logicalInput),
        sourceRef: source.sourceRef,
        sourceContractCid: source.sourceContractCid,
        authorityScopeCid, dataPolicyCid: source.sourceDataPolicyCid,
        captureStartedAt, captureCompletedAt}, limits)
      : control.issueCheckedClientSerializationInvocation(content.compiled,
        runDefinition, content.generation, limits);
  const sourceEvidence = control.admitRunEvidence('source_evidence',
    sourceEvidenceWire, limits);
  const dataPolicyCid = content === undefined ? source.sourceDataPolicyCid
    : JSON.parse(observation.wire).data_policy_cid;
  const run = JSON.parse(runDefinition.wire);
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
    retentionSelection: acquired.selectRetention?.()});
  let sourceRetention = retention;
  if (content !== undefined) {
    const body = JSON.parse(retention.wire);
    delete body.effective_retention_policy_cid;
    body.effective_data_policy_cid = source.sourceDataPolicyCid;
    sourceRetention = control.seal('result_retention_policy', JSON.stringify(body), limits);
  }
  const acquiredEvidence = control.issueCheckedAcquiredEffectEvidence(
    prepared, captured.capture.source(), captured.identity,
    captured.requirement, captured.logicalInput, sourceEvidence,
    authorityScopeCid, source.sourceDataPolicyCid, sourceRetention, limits, 0, retention);
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
      acquiredEvidence, retentionDependencies, acquisitionDependencies,
      ...(content === undefined ? {} : {acquiredCatalogBodies: Object.freeze([
        ...acquiredEvidence.catalogBodies,
        ...checked(moon.clientProgramEffectPublicationPolicyBodies(prepared,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth)).map(body =>
          Object.freeze({kind: runtimeField(body, 0), cid: runtimeField(body, 1), wire: runtimeField(body, 2)})),
      ])}),
      sourceLocalInvocation: acquiredEvidence.invocation,
      runInvocation: invocation, observation})});
}

// Retain the actual upstream Unit semantics before opening the first Model.
// The existing group owns this cache and its dispatch borrow through cleanup;
// no complete Model/Run observation or physical publication is claimed here.
export function prepareAcquiredEffectSourceUnits({acquired, sources, sourcePlan, managedRun, modelUnits}) {
  if (!Array.isArray(sources) || !Array.isArray(modelUnits)) {
    throw new TypeError('WholeEffectProducerUnitOriginalRequired');
  }
  const units = new Map();
  for (const {captured} of sources) {
    const unit = captured.occurrence?.stage;
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
  const retention = issueLocalResultRetention(control, policy, acquired.selectRetention());
  const evidence = sources.map(source => source.sourceEvidence === undefined
    ? control.admitRunEvidence('source_evidence', source.sourceEvidenceWire, limits) : source.sourceEvidence);
  const inputs = control.prepareCheckedInstalledEffectSourceUnits(sourcePlan, acquired.prepared,
    acquired.requestIdentity, acquired.compilation, acquired.admission, acquired.definition,
    sources, evidence, {authorityScopeCid: acquired.authorityScopeCid, dataPolicyCid: policy}, limits);
  const byUnit = new Map();
  for (const [unit] of selected) {
    // This record is installed before the Resource current/resize callbacks.
    // Reentry or a failed constructor never obtains a second original body.
    const entry = {preparing: true, value: undefined};
    byUnit.set(unit, entry);
    entry.value = control.prepareInstalledEffectModelSourceUnit(managedRun, sourcePlan,
      acquired.requestIdentity, inputs, unit, retention, limits);
    entry.preparing = false;
  }
  return Object.freeze({managedRun, sourcePlan, request: acquired.requestIdentity,
    sources, inputs, retention, byUnit});
}

// Both acquired tuples remain checked by the common Effect owner. Source
// input retention carries each original policy; derived publication carries
// the checked combined policy with exactly the same custody/time bounds.
export function acquiredMultiEffectPublicationPlan({acquired, sources,
  captureStartedAt, captureCompletedAt, issuedModel, modelOriginal, modelOriginals = modelOriginal === undefined ? [] : [modelOriginal], modelEvidence = [], keyedSource, sourcePlan, managedRun, sourceUnitsOriginal}) {
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
    ? control.admitRunEvidence('source_evidence', source.sourceEvidenceWire, limits)
    : source.sourceEvidence);
  const sourceUnits = new Map();
  for (const {captured} of sources) {
    const unit = captured.occurrence?.stage;
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
  const {observation, invocation, owner: invocationOwner, sourcePublication} = direct
    ? control.issueCheckedInstalledEffectDirectSourcesInvocation(sourcePlan, prepared,
      acquired.requestIdentity, compilation, admission, definition, sources, sourceEvidence, context, limits)
    : issuedModel === undefined ? control.issueCheckedClientEffectMultiCapturedInvocation(
      prepared, compilation, admission, definition, sources,
      context,
      limits) : control.checkedClientEffectInferInvocation(prepared,
        compilation, runDefinition, issuedModel);
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
  const run = JSON.parse(runDefinition.wire);
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
    retentionSelection: acquired.selectRetention?.(), originalRetention: sourceUnitsOriginal?.retention});
  const acquisitionDependencies = [];
  const acquiredEvidenceByUnit = [];
  for (const [slot, {captured}] of sources.entries()) {
    const unit = captured.occurrence?.stage;
    if (!Number.isSafeInteger(unit) || unit < 0) {
      throw new TypeError('OriginalEffectSourceCoordinateRequired');
    }
    // Inline Query/Whole inputs contribute to this SAME Model Unit. Their
    // complete evidence is issued from its retained Model observation below,
    // never through the Query-only single-Source Unit entrance.
    const modelContribution = issuedModel !== undefined && modelOriginals.some(model => model.unit === unit);
    if (!modelContribution && sourceUnits.get(unit) > 1) {
      if (acquiredEvidenceByUnit[unit] === undefined) {
        if (sourceUnitInputs !== undefined) {
          const original = sourceUnitsOriginal?.byUnit.get(unit);
          if (sourceUnitsOriginal !== undefined && (original === undefined || original.preparing || original.value === undefined)) {
            throw new TypeError('OriginalEffectSourceUnitUnavailable');
          }
          acquiredEvidenceByUnit[unit] = original?.value ?? control.prepareInstalledEffectModelSourceUnit(
            managedRun, sourcePlan, acquired.requestIdentity, sourceUnitInputs, unit, retention, limits);
        } else {
          if (sourcePublication === undefined) {
            throw new TypeError('CombinedEffectProducerUnitOriginalRequired');
          }
          acquiredEvidenceByUnit[unit] = control.prepareCombinedEffectSourceUnit(
            sourcePublication, unit, retention, limits);
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
          captured.logicalInput, sourceEvidence[slot], authorityScopeCid, retention, limits);
      } else {
        if (captured.requirement === undefined) {
          throw new TypeError('QueryEffectProducerUnitOriginalRequired');
        }
        const body = JSON.parse(retention.wire);
        delete body.effective_retention_policy_cid;
        body.effective_data_policy_cid = captured.checkedSource.sourceDataPolicyCid;
        const sourceRetention = control.seal('result_retention_policy',
          JSON.stringify(body), limits);
        acquiredEvidenceByUnit[unit] = control.issueCheckedAcquiredEffectEvidence(
          prepared, captured.capture.source(), captured.identity,
          captured.requirement, captured.logicalInput, sourceEvidence[slot],
          authorityScopeCid, captured.checkedSource.sourceDataPolicyCid,
          sourceRetention, limits, unit, retention);
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
      acquiredEvidence: acquiredEvidenceByUnit[0],
      acquiredEvidenceByUnit: Object.freeze(acquiredEvidenceByUnit),
      ...(sourceUnitsOriginal === undefined ? {} : {originalUnitResults: sourceUnitsOriginal.byUnit}),
      ...(modelOriginals.length === 0 ? {} : {
        modelOriginalByUnit: Object.freeze(Object.fromEntries(modelOriginals.map(model => [model.unit, model]))),
        modelRetention: retention,
      }),
      acquiredCatalogBodies: Object.freeze([
        ...acquiredEvidenceByUnit.flatMap(value => value.catalogBodies),
        ...checked(moon.clientProgramEffectPublicationPolicyBodies(prepared,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth)).map(body =>
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
  captureStartedAt, captureCompletedAt, keyedSource, signal, sourcePlan, managedRun, sourceUnitsOriginal, fundingOperation = operation, current, retainBinding}) {
  if (!Array.isArray(operations) || operations.length === 0 || operations[0] !== operation ||
      new Set(operations).size !== operations.length) {
    throw new TypeError('OriginalEffectModelInventoryRequired');
  }
  const issuedModels = [], modelOriginals = [];
  // Earlier Model scans stay in this group's original custody; count that
  // retained overlap before constructing any later final-issuer metadata.
  const earlierUnits = [...(sourceUnitsOriginal?.byUnit.values() ?? [])]
    .filter(entry => entry.results?.modelOriginal !== undefined);
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
        issuedModel: issued, modelOriginals, modelEvidence}).plan
      : acquiredMultiEffectPublicationPlan({acquired, sources,
        captureStartedAt, captureCompletedAt, issuedModel: issued, modelOriginals, modelEvidence, keyedSource, sourcePlan, managedRun, sourceUnitsOriginal});
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

export function sourceFreeValuesPlan({moon, control, preparedProgram,
  authorityScopeCid, namespaceId, storeAuthorityCid, now,
  retainedDefinitionWire, requestIdentity, publicationOriginal, compilationOriginal, publicationPreparation, invocationOriginal}) {
  const original = invocationOriginal === undefined ? undefined : checkedOriginalQueryInvocation(
    invocationOriginal, control, preparedProgram, requestIdentity, 'values', retainedDefinitionWire);
  const at = original === undefined ? Date.parse(now()) : undefined;
  if (original === undefined && !Number.isFinite(at)) throw new TypeError('InvalidLocalClock');
  const retained = retainedDefinitionWire === undefined ? undefined :
    JSON.parse(retainedDefinitionWire);
  const queryInvocation=original === undefined && publicationPreparation === undefined
    ? prepareQueryInvocation(control,preparedProgram,requestIdentity,retained) : undefined;
  const createdAt = original?.createdAt ?? retained?.created_at ?? queryInvocation?.createdAt ?? instant(at);
  const validUntil = original?.validUntil ?? retained?.valid_until ??
    instant(at + 24 * 60 * 60 * 1000);
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
  const plan = localPublicationPlan({control, admission, runDefinition, invocation,
    observation, compiledPlanCid: compiledPlan.identity,
    programDefinitionCid: moon.clientProgramDefinitionCid(preparedProgram),
    inputRelationCids: [], sourceEvidence: [], authorityScopeCid,
    namespaceId, storeAuthorityCid, dataPolicyCid, createdAt,
    now, resultCount: moon.clientProgramResultCount(preparedProgram),
    compiled, preparedProgram,
    // The existing Result owner retains one row index per unsorted row.
    // Consume the common checked Result envelope and publication policy;
    // the adapter does not infer workspace or field bounds from output rows.
    outputLimits: checkedLocalOutputLimits(moon, preparedProgram, publicationOriginal),
  });
  valuesAdmissions.set(plan, Object.freeze({
    prepared: compiled.preparedEvidence.wire,
    authorization: compiled.authorization.wire,
  }));
  return retainOriginalPlan(plan, compiled, preparedProgram, control, queryTime);
}

// Admit the complete checked task graph, including acquired sources, to the
// same portable Run owner used by the installed source-free profile. Physical
// acquisition and Source Evidence must still be established before this Run
// can be published; this admission alone never authorizes provider I/O.
export function acquiredTaskRunAdmission(options) {
  return checkedTaskRunAdmission(options, 'tasks');
}

// The model graph belongs to the original prepared Program. Compilation
// verifies that ownership; no source-free Observation Set is issued for a
// model barrier. Capture and its common issuer must supply it after dispatch.
export function inferTaskRunAdmission(options) {
  if (options.inferGraph === undefined) {
    throw new TypeError('MissingInstalledInferGraph');
  }
  return checkedTaskRunAdmission(options, 'infer');
}

// Reuse the admitted original Run and its compiler-owned graph. This is not
// fresh authorization, a new expiry, a replacement execution or a new Ledger.
// Select metadata from this restored compiler's existing opaque inventory.
// Coordinates identify the checked occurrence, never a new execution owner.
export function selectRestoredInferOccurrence({moon, control, preparedProgram, restored, occurrence}) {
  control.checkRestoredClientInferRunOwner(restored, preparedProgram);
  if (!Array.isArray(restored.graph)) {
    const original = control.checkedClientCompiledInferOriginal(
      restored.compiled, preparedProgram, restored.runDefinition);
    if (original.graph !== restored.graph) throw new TypeError('ForeignInstalledInferOriginalGraph');
    return original;
  }
  const originals = control.checkedClientCompiledInferOriginals(
    restored.compiled, preparedProgram, restored.runDefinition);
  if (originals.length !== restored.graph.length || occurrence === undefined ||
      originals.some((original, index) => original.graph !== restored.graph[index])) {
    throw new TypeError('ForeignInstalledInferOriginalGraph');
  }
  const coordinates = moon.clientProgramInferOccurrenceCoordinates(occurrence);
  const selected = originals.filter(original => {
    const boundary = moon.clientProgramInferPlanBoundary(original.graph);
    return runtimeField(boundary, 0) === runtimeField(coordinates, 0) &&
      runtimeField(boundary, 1) === runtimeField(coordinates, 1);
  });
  if (selected.length !== 1) throw new TypeError('ForeignInstalledInferOriginalOccurrence');
  return selected[0];
}

export function restoreInferTaskRunAdmission({control, preparedProgram, restored, requestIdentity}) {
  control.checkRestoredClientInferRunOwner(restored, preparedProgram);
  if (restored.compiled.kind !== 'infer') {
    throw new TypeError('ForeignInstalledInferOriginalRun');
  }
  const {compiled, runDefinition} = restored;
  const originals = Array.isArray(restored.graph)
    ? control.checkedClientCompiledInferOriginals(compiled, preparedProgram, runDefinition)
    : [control.checkedClientCompiledInferOriginal(compiled, preparedProgram, runDefinition)];
  const graphs = Array.isArray(restored.graph) ? restored.graph : [restored.graph];
  if (originals.length !== graphs.length ||
      originals.some((original, index) => original.graph !== graphs[index])) {
    throw new TypeError('ForeignInstalledInferOriginalGraph');
  }
  const queryInvocation=prepareQueryInvocation(control,preparedProgram,requestIdentity,
    JSON.parse(runDefinition.wire));
  const queryTime=bindQueryInvocation(control,queryInvocation,preparedProgram,compiled,runDefinition);
  return Object.freeze({...compiled, compiled, runDefinition, requestIdentity,
    ...queryTime,
    createdAt: JSON.parse(runDefinition.wire).created_at, inferGraph: restored.graph});
}

// Select the original checked Content occurrence, not a second parsed Program
// or a pure Values fallback. Physical generation must still supply its actual
// input/generation observations before publication can issue an Invocation.
export function serializationTaskRunAdmission(options) {
  const serializationGraph = options.serializationGraph ?? selectInstalledSerializationGraph(options);
  return checkedTaskRunAdmission({...options, serializationGraph}, 'serialization');
}

// Both terminal publication and an intermediate Model input select the same
// installed ceilings and original checked occurrence. Only root ownership differs.
export function selectInstalledSerializationGraph(options, component = false) {
  const {moon, control, preparedProgram} = options;
  const effectful = options.effectful === true;
  if (effectful && (!component || typeof options.prepareSerializationGraph !== 'function')) {
    throw new TypeError('InstalledContentComponentUnsupported');
  }
  const occurrences = (effectful ? moon.clientProgramEffectSerializationOccurrences
    : moon.clientProgramSerializationOccurrences)(preparedProgram);
  if (!Array.isArray(occurrences) || occurrences.length !== 1) {
    throw new TypeError('InstalledContentComponentUnsupported');
  }
  const occurrence = occurrences[0];
  const selected = {task: runtimeField(occurrence, 0), step: runtimeField(occurrence, 1),
      maxRows: localOutputLimits.maxRows, maxBytes: localOutputLimits.maxWireBytes,
      resultDataPolicy: options.resultDataPolicy ?? inferResultPolicy};
  if (options.prepareSerializationGraph !== undefined) {
    return options.prepareSerializationGraph(selected, component);
  }
  const serializationGraph = moon.clientProgramAcquisitionCount(preparedProgram) === 0
    ? component
      ? control.prepareCheckedClientSerializationComponent(preparedProgram, selected)
      : control.prepareCheckedClientSerializationGraph(preparedProgram, selected)
    : component
      ? control.prepareCheckedClientAcquiredSerializationComponent(preparedProgram, selected)
      : control.prepareCheckedClientAcquiredSerializationGraph(preparedProgram, selected);
  return serializationGraph;
}

// Physical generation discharges the already-admitted Content component.
// Reuse the normal Result retention/publication plan and add only its original
// typed Content proofs. No caller-composed observation or second Run is used.
export function serializationTaskPublicationPlan({moon, control, preparedProgram,
  admitted, generation, authorityScopeCid, namespaceId, storeAuthorityCid, now,
  sourceEvidence = [], outputLimits = localOutputLimits}) {
  control.checkClientCompiledRunOwner(admitted.compiled, preparedProgram);
  if (admitted.kind !== 'serialization') {
    throw new TypeError('InvalidContentPublicationAdmission');
  }
  const issued = control.issueCheckedClientSerializationInvocation(admitted.compiled,
    admitted.runDefinition, generation, limits);
  const bindings = control.checkedClientSerializationRecoveryBindings(admitted.compiled,
    generation, storeAuthorityCid);
  const input = bindings.find(binding => binding.name === 'content_input_artifact');
  if (input === undefined) throw new TypeError('ContentPublicationInputMissing');
  const observation = JSON.parse(issued.observation.wire);
  const plan = localPublicationPlan({control, admission: admitted.admission,
    runDefinition: admitted.runDefinition, invocation: issued.invocation,
    observation: issued.observation, compiledPlanCid: admitted.compiledPlan.identity,
    programDefinitionCid: moon.clientProgramDefinitionCid(preparedProgram),
    inputRelationCids: [JSON.parse(input.wire).logical_relation_cid], sourceEvidence,
    authorityScopeCid, namespaceId, storeAuthorityCid,
    dataPolicyCid: observation.data_policy_cid, createdAt: admitted.createdAt, now,
    resultCount: moon.clientProgramResultCount(preparedProgram), outputLimits,
    compiled: admitted.compiled, preparedProgram});
  const contentGenerations = Object.freeze([generation]);
  return Object.freeze({...plan,
    receiptEvidence: Object.freeze({...plan.receiptEvidence, contentGenerations}),
    captureEvidence: Object.freeze({...plan.captureEvidence, contentGenerations})});
}

// Only the common issuer can attach a model observation to this exact Run.
// Retention and Result evidence reuse the ordinary publication plan. The
// caller owns the returned binding until all Store users have settled.
export function inferTaskPublicationPlan({moon, control, preparedProgram,
  admitted, operation, issuance, modelEvidence, sourceEvidence = [], authorityScopeCid, namespaceId,
  storeAuthorityCid, now}) {
  control.checkClientCompiledRunOwner(admitted.compiled, preparedProgram);
  if (admitted.kind !== 'infer' || !Array.isArray(modelEvidence)) {
    throw new TypeError('InvalidInferPublicationAdmission');
  }
  const issued = operation.bindIssuedInvocation(control, {
    compiled: admitted.compiled, runDefinition: admitted.runDefinition,
    issued: issuance});
  try {
    const observation = JSON.parse(issued.observation.wire);
    const plan = localPublicationPlan({control,
      admission: admitted.admission, runDefinition: admitted.runDefinition,
      invocation: issued.invocation, observation: issued.observation,
      compiledPlanCid: admitted.compiledPlan.identity,
      programDefinitionCid: moon.clientProgramDefinitionCid(preparedProgram),
      inputRelationCids: observation.captured_input_artifact_cids,
      sourceEvidence, modelEvidence, authorityScopeCid, namespaceId,
      storeAuthorityCid, dataPolicyCid: observation.data_policy_cid,
      createdAt: admitted.createdAt, now,
      resultCount: moon.clientProgramResultCount(preparedProgram),
      compiled: admitted.compiled, preparedProgram});
    const contentGenerations = operation.contentGenerations?.();
    const completePlan = contentGenerations === undefined ? plan : Object.freeze({...plan,
      receiptEvidence: Object.freeze({...plan.receiptEvidence, contentGenerations}),
      captureEvidence: Object.freeze({...plan.captureEvidence, contentGenerations})});
    return Object.freeze({plan: completePlan, ...issued});
  } catch (error) {
    moon.clientProgramReleaseInferInvocationBinding(issued.binding);
    throw error;
  }
}

function checkedTaskRunAdmission({control, preparedProgram, inferGraph, serializationGraph,
  authorityScopeCid, namespaceId, now, retainedDefinitionWire, resultDataPolicy, requestIdentity, compilationOriginal, publicationPreparation, invocationOriginal}, kind) {
  const original = invocationOriginal === undefined ? undefined : checkedOriginalQueryInvocation(
    invocationOriginal, control, preparedProgram, requestIdentity, kind, retainedDefinitionWire);
  const at = original === undefined ? Date.parse(now()) : undefined;
  if (original === undefined && !Number.isFinite(at)) throw new TypeError('InvalidLocalClock');
  const retained = retainedDefinitionWire === undefined ? undefined :
    JSON.parse(retainedDefinitionWire);
  const queryInvocation=original === undefined && !(kind === 'tasks' && publicationPreparation !== undefined)
    ? prepareQueryInvocation(control,preparedProgram,requestIdentity,retained) : undefined;
  const createdAt = original?.createdAt ?? retained?.created_at ?? queryInvocation?.createdAt ?? instant(at);
  const validUntil = original?.validUntil ?? retained?.valid_until ??
    instant(at + 24 * 60 * 60 * 1000);
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
    ...queryTime,
    ...(kind === 'infer' ? {inferGraph} : {}),
    ...(kind === 'serialization' ? {serializationGraph} : {})});
  return kind === 'tasks' ? retainOriginalPlan(admitted, compiled, preparedProgram, control, queryTime) : admitted;
}

// Multi-task source-free Programs use the common task compiler and the same
// empty initial input set. No source observation is invented for Values roots.
export function sourceFreeTaskPlan(options) {
  const acquired = acquiredTaskRunAdmission(options);
  const {moon, control, preparedProgram, authorityScopeCid, namespaceId,
    storeAuthorityCid, now, publicationOriginal, publicationPreparation} = options;
  const dataPolicyCid = policyCid('local-result-data');
  const {observation, invocation} = control.issueCheckedClientCompiledInvocation(
    acquired.compiled, acquired.runDefinition, {dataPolicyCid}, limits,
    publicationPreparation, preparedProgram);
  const plan = localPublicationPlan({control, admission: acquired.admission,
    runDefinition: acquired.runDefinition, invocation, observation,
    compiledPlanCid: acquired.compiledPlan.identity,
    programDefinitionCid: moon.clientProgramDefinitionCid(preparedProgram),
    inputRelationCids: [], sourceEvidence: [], authorityScopeCid, namespaceId,
    storeAuthorityCid, dataPolicyCid, createdAt: acquired.createdAt, now,
    resultCount: moon.clientProgramResultCount(preparedProgram),
    compiled: acquired.compiled, preparedProgram,
    outputLimits: checkedLocalOutputLimits(moon, preparedProgram, publicationOriginal)});
  valuesAdmissions.set(plan, Object.freeze({prepared: acquired.preparedEvidence.wire,
    authorization: acquired.authorization.wire}));
  originalPlans.set(plan, originalPlans.get(acquired));
  return plan;
}

// The connector/Acquisition owner supplies Source Evidence after completing
// physical capture and current authorization. This Host binds that evidence to
// the checked task Run and the captured relation before publication.
export function acquiredTaskPublicationPlan({moon, control, acquired,
  preparedProgram, publicationOriginal, captured, sourceEvidence, authorityScopeCid,
  effectiveDataPolicyCid, captureStartedAt, captureCompletedAt, namespaceId,
  storeAuthorityCid, now}) {
  control.checkClientCompiledRunOwner(acquired.compiled, preparedProgram);
  if (sourceEvidence === undefined ||
      typeof effectiveDataPolicyCid !== 'string' ||
      captured?.logicalInput === undefined ||
      captured?.checkedSource === undefined ||
      captured?.identity === undefined ||
      captured?.capture === undefined ||
      moon.clientProgramCapturedSourceMatches(preparedProgram,
        captured.capture.source()) !== true) {
    throw new TypeError('InvalidAcquiredTaskPublication');
  }
  const {observation, invocation} = control.issueCheckedClientCompiledInvocation(
    acquired.compiled, acquired.runDefinition,
    {dataPolicyCid: effectiveDataPolicyCid, source: {captured, sourceEvidence,
      authorityScopeCid, captureStartedAt, captureCompletedAt}}, limits,
    acquired.publicationPreparation, preparedProgram);
  return localPublicationPlan({control, admission: acquired.admission,
    runDefinition: acquired.runDefinition, invocation, observation,
    compiledPlanCid: acquired.compiledPlan.identity,
    programDefinitionCid: moon.clientProgramDefinitionCid(preparedProgram),
    inputRelationCids: [moon.clientProgramCapturedSourceLogicalCid(
      captured.identity)], sourceEvidence: [sourceEvidence],
    authorityScopeCid, namespaceId, storeAuthorityCid,
    dataPolicyCid: effectiveDataPolicyCid, createdAt: acquired.createdAt,
    now, resultCount: moon.clientProgramResultCount(preparedProgram),
    compiled: acquired.compiled, preparedProgram,
    ...(publicationOriginal === undefined ? {} : {
      outputLimits: checkedLocalOutputLimits(moon, preparedProgram, publicationOriginal),
    })});
}


// The existing checked publication owner receives the complete occurrence
// inventory. Each source evidence retains its own read policy; the final
// publication policy is the checker's join of exact Result contributors.
export function acquiredMultiTaskPublicationPlan({moon, control, acquired,
  preparedProgram, publicationOriginal, sources, authorityScopeCid, effectiveDataPolicyCid,
  captureStartedAt, captureCompletedAt, namespaceId, storeAuthorityCid, now}) {
  control.checkClientCompiledRunOwner(acquired.compiled, preparedProgram);
  const whole = Array.isArray(sources) && sources.some(({captured}) => captured?.inputKind === 'whole-input');
  if (!Array.isArray(sources) || sources.length < 1 ||
      moon.clientProgramPublicationDataPolicyCid(preparedProgram) !== effectiveDataPolicyCid ||
      sources.some(({captured, sourceEvidence}, task) =>
        sourceEvidence === undefined || captured?.logicalInput === undefined ||
        captured?.identity === undefined || (whole
          ? captured.inputKind !== 'whole-input' || captured.wholeCapacity === undefined ||
            typeof captured.capture?.originalWholeInput !== 'function' || acquired.publicationPreparation === undefined
          : captured?.requirement === undefined ||
            !moon.clientProgramCapturedTaskSourceMatches(preparedProgram, captured.capture.source(), task)))) {
    throw new TypeError('InvalidAcquiredTaskPublication');
  }
  const observed = sources;
  const {observation, invocation} = control.issueCheckedClientCompiledInvocation(
    acquired.compiled, acquired.runDefinition, {source: {sources: observed, authorityScopeCid,
      captureStartedAt, captureCompletedAt}, dataPolicyCid: effectiveDataPolicyCid}, limits,
    acquired.publicationPreparation, preparedProgram);
  return localPublicationPlan({control, admission: acquired.admission,
    runDefinition: acquired.runDefinition, invocation, observation,
    compiledPlanCid: acquired.compiledPlan.identity,
    programDefinitionCid: moon.clientProgramDefinitionCid(preparedProgram),
    // Result derivation records a unique set of logical content dependencies.
    // Equal content does not coalesce the occurrence-owned captures or either
    // Source Evidence entry retained above in the Observation Set.
    inputRelationCids: [...new Set(sources.map(source =>
      moon.clientProgramCapturedSourceLogicalCid(source.captured.identity)))],
    sourceEvidence: observed.map(source => source.sourceEvidence),
    authorityScopeCid, namespaceId, storeAuthorityCid,
    dataPolicyCid: effectiveDataPolicyCid, createdAt: acquired.createdAt,
    now, resultCount: moon.clientProgramResultCount(preparedProgram),
    compiled: acquired.compiled, preparedProgram,
    ...(publicationOriginal === undefined ? {} : {
      outputLimits: checkedLocalOutputLimits(moon, preparedProgram, publicationOriginal),
    })});
}

// A keyed JOIN completes a second Source, not a second Direct task prefix.
// Retain both Source evidence entries while reusing the admitted compilation
// and the ordinary Result publication/retention plan.
export function acquiredKeyedTaskPublicationPlan({moon, control, acquired,
  preparedProgram, publicationOriginal, captured, sourceEvidence, keyedObservation,
  authorityScopeCid, effectiveDataPolicyCid, captureStartedAt, captureCompletedAt,
  namespaceId, storeAuthorityCid, now}) {
  control.checkClientCompiledRunOwner(acquired.compiled, preparedProgram);
  if (sourceEvidence === undefined ||
      captured?.logicalInput === undefined || captured?.identity === undefined ||
      captured?.requirement === undefined || captured?.capture === undefined ||
      keyedObservation?.observation === undefined ||
      moon.clientProgramPublicationDataPolicyCid(preparedProgram) !== effectiveDataPolicyCid ||
      moon.clientProgramCapturedSourceMatches(preparedProgram, captured.capture.source()) !== true) {
    throw new TypeError('InvalidAcquiredTaskPublication');
  }
  const right = control.keyedLookupPublicationEvidence(keyedObservation.observation);
  const left = sourceEvidence;
  const {observation, invocation} = control.issueCheckedClientCompiledInvocation(
    acquired.compiled, acquired.runDefinition, {source: {captured, sourceEvidence: left,
      keyedObservation: keyedObservation.observation, authorityScopeCid,
      captureStartedAt, captureCompletedAt}, dataPolicyCid: effectiveDataPolicyCid}, limits,
    acquired.publicationPreparation, preparedProgram);
  return localPublicationPlan({control, admission: acquired.admission,
    runDefinition: acquired.runDefinition, invocation, observation,
    compiledPlanCid: acquired.compiledPlan.identity,
    programDefinitionCid: moon.clientProgramDefinitionCid(preparedProgram),
    inputRelationCids: [...new Set([
      moon.clientProgramCapturedSourceLogicalCid(captured.identity),
      right.logicalRelationCid,
    ])],
    sourceEvidence: [left, right.source],
    authorityScopeCid, namespaceId, storeAuthorityCid,
    dataPolicyCid: effectiveDataPolicyCid, createdAt: acquired.createdAt,
    now, resultCount: moon.clientProgramResultCount(preparedProgram),
    compiled: acquired.compiled, preparedProgram,
    ...(publicationOriginal === undefined ? {} : {
      outputLimits: checkedLocalOutputLimits(moon, preparedProgram, publicationOriginal),
    })});
}
