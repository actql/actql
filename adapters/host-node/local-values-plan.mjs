// Bind the installed source-free compiler to the common Run and publication
// owner. Physical Local policy CIDs are stable identities of this Host profile.
import {runtimeField, runtimeOptionalField} from '../host-common/compiler-binding.generated.mjs';
import {createHash, randomUUID} from 'node:crypto';
import {checked} from '../host-common/runtime-result.mjs';
import {valuesHostPolicyOriginal, valuesExecutionContextCid} from './local-values-capacity.mjs';
import {sampleOriginalQueryTime} from './query-evaluation-clock.mjs';

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

// Contract and evidence issuance bounds. A captured Run's Named Result
// snapshot is admitted under them too, so they hold what one captured Run can
// output: the Local import wire (1 MB, 100k nodes).
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
export const localContractLimits = limits;

const cid = value => `sha256:${createHash('sha256')
  .update(JSON.stringify(value)).digest('hex')}`;
const policyCid = name => cid({version: 'actql-installed-local-policy/0.1',
  name});
const valuesAdmissions = new WeakMap();
const originalPlans = new WeakMap();
const originalPlanLimits = Object.freeze({maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64});
export function sourceFreePlanOriginal(plan) {return originalPlans.get(plan);}

function retainOriginalPlan(plan, compiled, preparedProgram, control) {
  originalPlans.set(plan, control.captureOriginalClientRunPlan(
    compiled, preparedProgram, plan.runDefinition, originalPlanLimits));
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

// Keep the retained input policy available to Effect evidence issuance
// without extending the closed publication-plan JS bridge used by ordinary Runs.
function buildLocalPublicationPlan({control, admission, runDefinition, invocation,
  observation, compiledPlanCid, programDefinitionCid, inputRelationCids,
  sourceEvidence, authorityScopeCid, namespaceId, storeAuthorityCid,
  dataPolicyCid, createdAt, now, resultCount, retainUntil,
  compiled, preparedProgram, effectCompilation, preparedEffect, moon,
  modelEvidence = [], outputLimits = localOutputLimits}) {
  const at = Date.parse(now());
  const availableAt = retainUntil === undefined ? at + 60 * 60 * 1000
    : Math.max(at + 60 * 60 * 1000, Date.parse(retainUntil));
  const availableUntil = instant(availableAt);
  const deleteBy = instant(availableAt + 60 * 60 * 1000);
  const metadataDeleteBy = instant(Math.max(at + 7 * 24 * 60 * 60 * 1000,
    availableAt + 2 * 60 * 60 * 1000));
  const retention = control.seal('result_retention_policy', JSON.stringify({
    version: 'actql-result-retention-policy/0.1',
    retention_contract_cid: retentionDependencies[0].cid,
    effective_data_policy_cid: dataPolicyCid,
    available_until: availableUntil, delete_by: deleteBy,
    extension_ceiling_at: metadataDeleteBy,
    metadata_retention_policy_cid: retentionDependencies[1].cid,
    metadata_delete_by: metadataDeleteBy,
    clock_contract_cid: retentionDependencies[2].cid,
  }), limits);
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
  storeAuthorityCid, now, resultDataPolicy}) {
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
  return Object.freeze({moon, control, prepared, compilation, allowed,
    definition, authorityScopeCid, namespaceId, storeAuthorityCid, now,
    admission, runDefinition, compiledPlan, dataPolicyCid, resultDataPolicy,
    resultDataPolicyLimits: limits});
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
    moon, effectCompilation: compilation, preparedEffect: prepared});
  return Object.freeze({...plan, effectInputRetention: retention, invocationOwner: runtimeField(sourceFree, 1),
    localEvidenceContext: Object.freeze({admission, runDefinition,
      runInvocation: invocation, observation})});
}

// The accepted Effect Run can be admitted before provider I/O, but its
// Observation Set cannot be issued until the exact acquired source exists.
export function acquiredEffectPublicationAdmission(options) {
  return effectPublicationAdmission(options);
}

// A source-free Model still issues its real Observation Set after dispatch.
// Keep the original Effect admission and bind that exact Model issuer instead
// of issuing a no-external-work observation during Run preparation.
export function sourceFreeInferEffectPublicationPlan({acquired,
  compiled, operation, issuance, modelEvidence}) {
  const {moon, control, prepared, compilation, admission, runDefinition,
    compiledPlan, authorityScopeCid, namespaceId, storeAuthorityCid, now} = acquired;
  const issued = operation.bindIssuedInvocation(control, {
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
      moon, effectCompilation: compilation, preparedEffect: prepared});
    return Object.freeze({...issued, plan: Object.freeze({...plan, effectInputRetention: retention,
      invocationOwner, localEvidenceContext: Object.freeze({admission,
        runDefinition, retentionDependencies: Object.freeze([...retentionDependencies,
          Object.freeze({kind: 'result_retention_policy',
            cid: retention.identity, wire: retention.wire})]),
        sourceFreeDependencyClosure:true,
        resultDataPolicy: control.compiledInferSourceFreeResultPolicy(compiled),
        runInvocation: invocation,
        observation})})});
  } catch (error) {
    moon.clientProgramReleaseInferInvocationBinding(issued.binding);
    throw error;
  }
}

export function acquiredEffectPublicationPlan({acquired, captured,
  sourceEvidenceWire, captureStartedAt, captureCompletedAt, content}) {
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
    moon, effectCompilation: compilation, preparedEffect: prepared});
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

// Both acquired tuples remain checked by the common Effect owner. Source
// input retention carries each original policy; derived publication carries
// the checked combined policy with exactly the same custody/time bounds.
export function acquiredMultiEffectPublicationPlan({acquired, sources,
  captureStartedAt, captureCompletedAt, issuedModel, modelEvidence = []}) {
  const {moon, control, prepared, compilation, definition, admission,
    runDefinition, compiledPlan, authorityScopeCid,
    namespaceId, storeAuthorityCid, now} = acquired;
  if (!Array.isArray(sources) || (issuedModel === undefined ? sources.length !== 2
    : ![1, 2].includes(sources.length))) {
    throw new TypeError('IncompleteAcquiredEffectSources');
  }
  const dataPolicyCid = moon.clientProgramEffectPublicationDataPolicyCid(prepared);
  if (typeof dataPolicyCid !== 'string') {
    throw new TypeError('UnavailableAcquiredEffectPolicy');
  }
  const {observation, invocation, owner: invocationOwner} =
    issuedModel === undefined ? control.issueCheckedClientEffectMultiCapturedInvocation(
      prepared, compilation, admission, definition, sources,
      {authorityScopeCid, dataPolicyCid, captureStartedAt, captureCompletedAt},
      limits) : control.checkedClientEffectInferInvocation(prepared,
        compilation, runDefinition, issuedModel);
  const sourceEvidence = sources.map(source => control.admitRunEvidence(
    'source_evidence', source.sourceEvidenceWire, limits));
  const run = JSON.parse(runDefinition.wire);
  const {plan, retention, retentionDependencies} = buildLocalPublicationPlan({
    control, admission, runDefinition, invocation, observation,
    compiledPlanCid: compiledPlan.identity,
    programDefinitionCid: moon.clientProgramEffectDefinitionCid(prepared),
    inputRelationCids: sources.map(({captured}) =>
      moon.clientProgramCapturedSourceLogicalCid(captured.identity)),
    sourceEvidence, modelEvidence, authorityScopeCid, namespaceId, storeAuthorityCid,
    dataPolicyCid, createdAt: run.created_at, now,
    resultCount: moon.clientProgramEffectCompilationResultNames(compilation).length,
    retainUntil: run.valid_until,
    moon, effectCompilation: compilation, preparedEffect: prepared});
  const acquisitionDependencies = [];
  const acquiredEvidenceByUnit = sources.map(({captured}, unit) => {
    const body = JSON.parse(retention.wire);
    delete body.effective_retention_policy_cid;
    body.effective_data_policy_cid = captured.checkedSource.sourceDataPolicyCid;
    const sourceRetention = control.seal('result_retention_policy',
      JSON.stringify(body), limits);
    const evidence = control.issueCheckedAcquiredEffectEvidence(
      prepared, captured.capture.source(), captured.identity,
      captured.requirement, captured.logicalInput, sourceEvidence[unit],
      authorityScopeCid, captured.checkedSource.sourceDataPolicyCid,
      sourceRetention, limits, unit, retention);
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
    return evidence;
  });
  return Object.freeze({...plan, effectInputRetention: retention, invocationOwner,
    localEvidenceContext: Object.freeze({admission, runDefinition,
      acquiredEvidence: acquiredEvidenceByUnit[0],
      acquiredEvidenceByUnit: Object.freeze(acquiredEvidenceByUnit),
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
export function acquiredInferEffectPublicationPlan({acquired, sources,
  compiled, operation, issuance, modelEvidence, captureStartedAt, captureCompletedAt}) {
  const issued = operation.bindIssuedInvocation(acquired.control, {
    compiled, runDefinition: acquired.runDefinition, issued: issuance});
  try {
    const plan = acquiredMultiEffectPublicationPlan({acquired, sources,
      captureStartedAt, captureCompletedAt, issuedModel: issued, modelEvidence});
    const contentGenerations = operation.contentGenerations?.();
    const completePlan = contentGenerations === undefined ? plan : Object.freeze({...plan,
      receiptEvidence: Object.freeze({...plan.receiptEvidence, contentGenerations}),
      captureEvidence: Object.freeze({...plan.captureEvidence, contentGenerations})});
    return Object.freeze({...issued, plan: completePlan});
  } catch (error) {
    acquired.moon.clientProgramReleaseInferInvocationBinding(issued.binding);
    throw error;
  }
}

export function sourceFreeValuesPlan({moon, control, preparedProgram,
  authorityScopeCid, namespaceId, storeAuthorityCid, now,
  retainedDefinitionWire, requestIdentity}) {
  const at = Date.parse(now());
  if (!Number.isFinite(at)) throw new TypeError('InvalidLocalClock');
  const retained = retainedDefinitionWire === undefined ? undefined :
    JSON.parse(retainedDefinitionWire);
  const queryInvocation=prepareQueryInvocation(control,preparedProgram,requestIdentity,retained);
  const createdAt = retained?.created_at ?? queryInvocation?.createdAt ?? instant(at);
  const validUntil = retained?.valid_until ??
    instant(at + 24 * 60 * 60 * 1000);
  const maxRows = moon.clientProgramValuesMaxRows(preparedProgram);
  const originalPolicy = valuesHostPolicyOriginal(maxRows);
  const hostPolicyCid = originalPolicy?.cid ?? policyCid('source-free-values');
  const contextCid = valuesExecutionContextCid(authorityScopeCid, originalPolicy);
  const compiled = control.prepareCheckedClientCompiledRun(preparedProgram,
    'values', {executionContextCid: contextCid,
      hostPolicyCid, expiresAt: validUntil});
  const {admission, compiledPlan} = compiled;
  const runDefinition = control.defineCheckedClientCompiledRun(compiled, {
    namespaceId, runId: randomUUID(), createdAt, validUntil,
    retainedDefinitionWire,
  });
  const queryTime=bindQueryInvocation(control,queryInvocation,preparedProgram,compiled,runDefinition);
  const dataPolicyCid = policyCid('local-result-data');
  const {observation, invocation} = control.issueCheckedClientCompiledInvocation(
    compiled, runDefinition, {dataPolicyCid}, limits);
  const plan = localPublicationPlan({control, admission, runDefinition, invocation,
    observation, compiledPlanCid: compiledPlan.identity,
    programDefinitionCid: moon.clientProgramDefinitionCid(preparedProgram),
    inputRelationCids: [], sourceEvidence: [], authorityScopeCid,
    namespaceId, storeAuthorityCid, dataPolicyCid, createdAt,
    now, resultCount: moon.clientProgramResultCount(preparedProgram),
    compiled, preparedProgram,
    // The existing Result owner retains one row index per unsorted row.
    // Follow the explicitly admitted row ceiling, preserving all other
    // Result, value, work, wire and Store bounds. Ordered views retain their
    // existing independent scratch requirement and can still be refused.
    outputLimits: Object.freeze({...localOutputLimits,
      maxResultWorkspaceEntries: Math.max(localOutputLimits.maxResultWorkspaceEntries, maxRows)}),
  });
  const selectedPlan=Object.keys(queryTime).length===0?plan:Object.freeze({...plan,...queryTime});
  valuesAdmissions.set(selectedPlan, Object.freeze({
    prepared: compiled.preparedEvidence.wire,
    authorization: compiled.authorization.wire,
    ...(originalPolicy === undefined ? {} : {valuesHostPolicyOriginal: originalPolicy}),
  }));
  return retainOriginalPlan(selectedPlan, compiled, preparedProgram, control);
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
export function restoreInferTaskRunAdmission({control, preparedProgram, restored, requestIdentity}) {
  control.checkRestoredClientInferRunOwner(restored, preparedProgram);
  if (restored.compiled.kind !== 'infer') {
    throw new TypeError('ForeignInstalledInferOriginalRun');
  }
  const {compiled, runDefinition} = restored;
  const original = control.checkedClientCompiledInferOriginal(compiled, preparedProgram, runDefinition);
  if (original.graph !== restored.graph) throw new TypeError('ForeignInstalledInferOriginalGraph');
  const queryInvocation=prepareQueryInvocation(control,preparedProgram,requestIdentity,
    JSON.parse(runDefinition.wire));
  const queryTime=bindQueryInvocation(control,queryInvocation,preparedProgram,compiled,runDefinition);
  return Object.freeze({...compiled, compiled, runDefinition,
    ...queryTime,
    createdAt: JSON.parse(runDefinition.wire).created_at, inferGraph: original.graph});
}

// Select the original checked Content occurrence, not a second parsed Program
// or a pure Values fallback. Physical generation must still supply its actual
// input/generation observations before publication can issue an Invocation.
export function serializationTaskRunAdmission(options) {
  const serializationGraph = selectInstalledSerializationGraph(options);
  return checkedTaskRunAdmission({...options, serializationGraph}, 'serialization');
}

// Both terminal publication and an intermediate Model input select the same
// installed ceilings and original checked occurrence. Only root ownership differs.
export function selectInstalledSerializationGraph(options, component = false) {
  const {moon, control, preparedProgram} = options;
  const occurrences = moon.clientProgramSerializationOccurrences(preparedProgram);
  if (!Array.isArray(occurrences) || occurrences.length !== 1) {
    throw new TypeError('InstalledContentComponentUnsupported');
  }
  const occurrence = occurrences[0];
  const selected = {task: runtimeField(occurrence, 0), step: runtimeField(occurrence, 1),
      maxRows: localOutputLimits.maxRows, maxBytes: localOutputLimits.maxWireBytes,
      resultDataPolicy: options.resultDataPolicy ?? inferResultPolicy};
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
  authorityScopeCid, namespaceId, now, retainedDefinitionWire, resultDataPolicy, requestIdentity}, kind) {
  const at = Date.parse(now());
  if (!Number.isFinite(at)) throw new TypeError('InvalidLocalClock');
  const retained = retainedDefinitionWire === undefined ? undefined :
    JSON.parse(retainedDefinitionWire);
  const queryInvocation=prepareQueryInvocation(control,preparedProgram,requestIdentity,retained);
  const createdAt = retained?.created_at ?? queryInvocation?.createdAt ?? instant(at);
  const validUntil = retained?.valid_until ??
    instant(at + 24 * 60 * 60 * 1000);
  const contextCid = cid({version: 'actql-installed-local-context/0.1',
    authority_scope_cid: authorityScopeCid});
  const compiled = control.prepareCheckedClientCompiledRun(preparedProgram,
    kind, {executionContextCid: contextCid,
      hostPolicyCid: policyCid(kind === 'infer' ? 'checked-infer'
        : kind === 'serialization' ? 'checked-content' : 'checked-tasks'),
      expiresAt: validUntil,
      ...(kind === 'infer' ? {resultDataPolicy: resultDataPolicy ?? inferResultPolicy} : {})},
    kind === 'serialization' ? serializationGraph : inferGraph);
  const {admission, compiledPlan} = compiled;
  const runDefinition = control.defineCheckedClientCompiledRun(compiled, {
    namespaceId, runId: randomUUID(), createdAt, validUntil,
    retainedDefinitionWire,
  });
  const queryTime=bindQueryInvocation(control,queryInvocation,preparedProgram,compiled,runDefinition);
  const admitted = Object.freeze({...compiled, compiled, runDefinition, createdAt,
    ...queryTime,
    ...(kind === 'infer' ? {inferGraph} : {}),
    ...(kind === 'serialization' ? {serializationGraph} : {})});
  return kind === 'tasks' ? retainOriginalPlan(admitted, compiled, preparedProgram, control) : admitted;
}

// Multi-task source-free Programs use the common task compiler and the same
// empty initial input set. No source observation is invented for Values roots.
export function sourceFreeTaskPlan(options) {
  const acquired = acquiredTaskRunAdmission(options);
  const {moon, control, preparedProgram, authorityScopeCid, namespaceId,
    storeAuthorityCid, now} = options;
  const dataPolicyCid = policyCid('local-result-data');
  const {observation, invocation} = control.issueCheckedClientCompiledInvocation(
    acquired.compiled, acquired.runDefinition, {dataPolicyCid}, limits);
  const plan = localPublicationPlan({control, admission: acquired.admission,
    runDefinition: acquired.runDefinition, invocation, observation,
    compiledPlanCid: acquired.compiledPlan.identity,
    programDefinitionCid: moon.clientProgramDefinitionCid(preparedProgram),
    inputRelationCids: [], sourceEvidence: [], authorityScopeCid, namespaceId,
    storeAuthorityCid, dataPolicyCid, createdAt: acquired.createdAt, now,
    resultCount: moon.clientProgramResultCount(preparedProgram),
    compiled: acquired.compiled, preparedProgram});
  const selectedPlan=acquired.queryTime===undefined?plan:Object.freeze({...plan,
    queryTimePreparation:acquired.queryTimePreparation,queryTime:acquired.queryTime});
  valuesAdmissions.set(selectedPlan, Object.freeze({prepared: acquired.preparedEvidence.wire,
    authorization: acquired.authorization.wire}));
  originalPlans.set(selectedPlan, sourceFreePlanOriginal(acquired));
  return selectedPlan;
}

// The connector/Acquisition owner supplies Source Evidence after completing
// physical capture and current authorization. This Host binds that evidence to
// the checked task Run and the captured relation before publication.
export function acquiredTaskPublicationPlan({moon, control, acquired,
  preparedProgram, captured, sourceEvidenceWire, authorityScopeCid,
  effectiveDataPolicyCid, captureStartedAt, captureCompletedAt, namespaceId,
  storeAuthorityCid, now}) {
  control.checkClientCompiledRunOwner(acquired.compiled, preparedProgram);
  if (typeof sourceEvidenceWire !== 'string' ||
      typeof effectiveDataPolicyCid !== 'string' ||
      captured?.logicalInput === undefined ||
      captured?.checkedSource === undefined ||
      captured?.identity === undefined ||
      captured?.capture === undefined ||
      moon.clientProgramCapturedSourceMatches(preparedProgram,
        captured.capture.source()) !== true) {
    throw new TypeError('InvalidAcquiredTaskPublication');
  }
  const inputLogicalWire = moon.strategyRunEvidenceJson(
    captured.logicalInput);
  const source = captured.checkedSource;
  const {observation, invocation} = control.issueCheckedClientCompiledInvocation(
    acquired.compiled, acquired.runDefinition,
    {dataPolicyCid: effectiveDataPolicyCid, source: {
      sourceEvidenceWire, inputLogicalWire,
      sourceRef: source.sourceRef,
      sourceContractCid: source.sourceContractCid,
      authorityScopeCid, captureStartedAt, captureCompletedAt,
    }}, limits);
  const sourceEvidence = control.admitRunEvidence('source_evidence',
    sourceEvidenceWire, limits);
  return localPublicationPlan({control, admission: acquired.admission,
    runDefinition: acquired.runDefinition, invocation, observation,
    compiledPlanCid: acquired.compiledPlan.identity,
    programDefinitionCid: moon.clientProgramDefinitionCid(preparedProgram),
    inputRelationCids: [moon.clientProgramCapturedSourceLogicalCid(
      captured.identity)], sourceEvidence: [sourceEvidence],
    authorityScopeCid, namespaceId, storeAuthorityCid,
    dataPolicyCid: effectiveDataPolicyCid, createdAt: acquired.createdAt,
    now, resultCount: moon.clientProgramResultCount(preparedProgram),
    compiled: acquired.compiled, preparedProgram});
}


// The existing checked publication owner receives the complete occurrence
// inventory. Each source evidence retains its own read policy; the final
// publication policy is the checker's join of exact Result contributors.
export function acquiredMultiTaskPublicationPlan({moon, control, acquired,
  preparedProgram, sources, authorityScopeCid, effectiveDataPolicyCid,
  captureStartedAt, captureCompletedAt, namespaceId, storeAuthorityCid, now}) {
  control.checkClientCompiledRunOwner(acquired.compiled, preparedProgram);
  if (!Array.isArray(sources) || sources.length !== 2 ||
      moon.clientProgramPublicationDataPolicyCid(preparedProgram) !== effectiveDataPolicyCid ||
      sources.some(({captured, sourceEvidenceWire}, task) =>
        typeof sourceEvidenceWire !== 'string' || captured?.logicalInput === undefined ||
        captured?.identity === undefined || captured?.requirement === undefined ||
        !moon.clientProgramCapturedTaskSourceMatches(preparedProgram, captured.capture.source(), task))) {
    throw new TypeError('InvalidAcquiredTaskPublication');
  }
  const observed = sources.map(source => ({...source,
    inputLogicalWire: moon.strategyRunEvidenceJson(source.captured.logicalInput)}));
  const {observation, invocation} = control.issueCheckedClientCompiledMultiInvocation(
    acquired.compiled, acquired.runDefinition, {sources: observed, authorityScopeCid,
      dataPolicyCid: effectiveDataPolicyCid, captureStartedAt, captureCompletedAt}, limits);
  return localPublicationPlan({control, admission: acquired.admission,
    runDefinition: acquired.runDefinition, invocation, observation,
    compiledPlanCid: acquired.compiledPlan.identity,
    programDefinitionCid: moon.clientProgramDefinitionCid(preparedProgram),
    // Result derivation records a unique set of logical content dependencies.
    // Equal content does not coalesce the occurrence-owned captures or either
    // Source Evidence entry retained above in the Observation Set.
    inputRelationCids: [...new Set(sources.map(source =>
      moon.clientProgramCapturedSourceLogicalCid(source.captured.identity)))],
    sourceEvidence: sources.map(source => control.admitRunEvidence('source_evidence',
      source.sourceEvidenceWire, limits)),
    authorityScopeCid, namespaceId, storeAuthorityCid,
    dataPolicyCid: effectiveDataPolicyCid, createdAt: acquired.createdAt,
    now, resultCount: moon.clientProgramResultCount(preparedProgram),
    compiled: acquired.compiled, preparedProgram});
}

// A keyed JOIN completes a second Source, not a second Direct task prefix.
// Retain both Source evidence entries while reusing the admitted compilation
// and the ordinary Result publication/retention plan.
export function acquiredKeyedTaskPublicationPlan({moon, control, acquired,
  preparedProgram, captured, sourceEvidenceWire, keyedObservation,
  authorityScopeCid, effectiveDataPolicyCid, captureStartedAt, captureCompletedAt,
  namespaceId, storeAuthorityCid, now}) {
  control.checkClientCompiledRunOwner(acquired.compiled, preparedProgram);
  if (typeof sourceEvidenceWire !== 'string' ||
      captured?.logicalInput === undefined || captured?.identity === undefined ||
      captured?.requirement === undefined || captured?.capture === undefined ||
      keyedObservation?.observation === undefined ||
      typeof keyedObservation.inputLogicalWire !== 'string' ||
      typeof keyedObservation.sourceEvidenceWire !== 'string' ||
      moon.clientProgramPublicationDataPolicyCid(preparedProgram) !== effectiveDataPolicyCid ||
      moon.clientProgramCapturedSourceMatches(preparedProgram, captured.capture.source()) !== true) {
    throw new TypeError('InvalidAcquiredTaskPublication');
  }
  // Read the wires from the same live opaque observation passed to issuance.
  // Callers cannot swap one completed lookup's text onto another lookup owner.
  const wires = moon.clientProgramKeyedLookupObservationWires(keyedObservation.observation);
  if (wires === undefined || runtimeField(wires, 0) !== keyedObservation.inputLogicalWire ||
      runtimeField(wires, 1) !== keyedObservation.sourceEvidenceWire) {
    throw new TypeError('InvalidAcquiredTaskPublication');
  }
  const {observation, invocation} = control.issueCheckedClientCompiledKeyedInvocation(
    acquired.compiled, acquired.runDefinition, {captured, sourceEvidenceWire,
      inputLogicalWire: moon.strategyRunEvidenceJson(captured.logicalInput),
      keyedObservation: keyedObservation.observation, authorityScopeCid,
      dataPolicyCid: effectiveDataPolicyCid, captureStartedAt, captureCompletedAt}, limits);
  // Both logical inputs have been validated by the portable issuer above.
  // Acquired Source relations are logical dependencies, not captured input
  // Artifacts. Do not omit the right Source's empty logical Relation.
  const keyedInput = JSON.parse(runtimeField(wires, 0));
  return localPublicationPlan({control, admission: acquired.admission,
    runDefinition: acquired.runDefinition, invocation, observation,
    compiledPlanCid: acquired.compiledPlan.identity,
    programDefinitionCid: moon.clientProgramDefinitionCid(preparedProgram),
    inputRelationCids: [...new Set([
      moon.clientProgramCapturedSourceLogicalCid(captured.identity),
      keyedInput.logical_relation_cid,
    ])],
    sourceEvidence: [sourceEvidenceWire, runtimeField(wires, 1)].map(wire =>
      control.admitRunEvidence('source_evidence', wire, limits)),
    authorityScopeCid, namespaceId, storeAuthorityCid,
    dataPolicyCid: effectiveDataPolicyCid, createdAt: acquired.createdAt,
    now, resultCount: moon.clientProgramResultCount(preparedProgram),
    compiled: acquired.compiled, preparedProgram});
}
