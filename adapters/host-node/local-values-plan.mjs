// Bind the installed source-free compiler to the common Run and publication
// owner. Physical Local policy CIDs are stable identities of this Host profile.
import {runtimeField, runtimeOptionalField} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {checkedPublicationLimitValues} from './local-publication-limit-projection.mjs';
import {localContractLimits as limits, localOutputLimits} from './local-publication-limits.mjs';
import {hostResultStorePolicy} from './host-result-service-recipe.cjs';
import {prepareQueryInvocation, bindQueryInvocation}
  from './local-query-invocation.mjs';
import {withOriginalInferModelObservation} from './infer-effect-observation.mjs';
import {retentionDependencies, localPublicationPlan, localRetentionTimes, buildLocalPublicationPlan,
  managedProgramPublicationCurrent, managedProgramInitialRetention, effectPublicationAdmission}
  from './local-publication-plan.mjs';
export {keyedInputRetentionSelection} from './local-publication-plan.mjs';
export {acquiredTaskPublicationPlan, acquiredMultiTaskPublicationPlan, acquiredKeyedTaskPublicationPlan}
  from './local-acquired-task-publication.mjs';
export {checkedLocalOutputLimits} from './local-publication-limit-projection.mjs';
export {prepareTimedClientInvocation} from './local-query-invocation.mjs';
export {localContractLimits, localOutputLimits} from './local-publication-limits.mjs';
import {checkedTaskRunAdmission, inferResultPolicy} from './local-source-free-plan.mjs';
export {acquiredTaskRunAdmission, sourceFreePlanOriginal, sourceFreePlanExplanation, sourceFreePlanExecutionOwner,
  sourceFreeTaskPlan, sourceFreeValuesAdmissionEvidence, sourceFreeValuesPlan} from './local-source-free-plan.mjs';

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

function finishSourceFreeEffectPublicationPlan(acquired, observation, invocation, invocationOwner,
  sourceFreeInvocationOriginal, managedRun, sourcePlan) {
  const {moon, control, prepared, compilation, admission, runDefinition,
    compiledPlan, dataPolicyCid, authorityScopeCid, namespaceId, storeAuthorityCid, now} = acquired;
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
    retentionSelection: acquired.selectRetention?.(),
    originalRetention: (managedRun === undefined ? undefined : control.issueInstalledEffectInitialRetention(managedRun, prepared,
      acquired.requestIdentity, sourcePlan, dataPolicyCid, acquired.selectRetention(), limits))});
  const result = {...plan, effectInputRetention: retention, invocationOwner,
    localEvidenceContext: Object.freeze({admission, runDefinition,
      runInvocation: invocation, observation})};
  if (sourceFreeInvocationOriginal !== undefined) result.sourceFreeInvocationOriginal = sourceFreeInvocationOriginal;
  return Object.freeze(result);
}

export function sourceFreeEffectPublicationPlan(options) {
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
export function sourceFreeEffectPublicationPlanOriginal(options) {
  const acquired = effectPublicationAdmission(options);
  const issued = acquired.control.issueCheckedClientEffectSourceFreeInvocationOriginal(
    acquired.compilation, acquired.dataPolicyCid, limits);
  return finishSourceFreeEffectPublicationPlan(acquired, issued.observation,
    issued.invocation, issued.owner, issued.original, options.managedRun, options.sourcePlan);
}

// The accepted Effect Run can be admitted before provider I/O, but its
// Observation Set cannot be issued until the exact acquired source exists.
export function acquiredEffectPublicationAdmission(options) {
  return effectPublicationAdmission(options);
}

// Source-free Content is generated before its real Observation Set is issued.
// Use the original Common generation and explicit compiled policy, without a
// fabricated Source capture, Model call, input relation or second Run.
export function sourceFreeContentEffectPublicationPlan({acquired,compiled,generation,
  managedRun, sourcePlan, sourceHost}) {
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
  const run=JSON.parse(runDefinition.wire);
  const {plan,retention,retentionDependencies}=buildLocalPublicationPlan({control,admission,
    runDefinition,invocation,observation,compiledPlanCid:compiledPlan.identity,
    programDefinitionCid:moon.clientProgramEffectDefinitionCid(prepared),
    inputRelationCids:JSON.parse(observation.wire).captured_input_artifact_cids,
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
export function sourceFreeInferEffectPublicationPlan({acquired,
  compiled, operation, issuance, modelEvidence, issuedModel, modelOriginals,
  managedRun, sourcePlan, sourceHost}) {
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
      retentionSelection: acquired.selectRetention?.(),
    originalRetention: (managedRun === undefined ? undefined : control.issueInstalledEffectInitialRetention(managedRun, prepared,
      acquired.requestIdentity, sourcePlan, JSON.parse(observation.wire).data_policy_cid, acquired.selectRetention(), limits))});
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

// One real captured Source and its completed keyed right input form the same
// checked Unit. Neither side is relabeled as Model or a single-Source result.
export function acquiredKeyedEffectPublicationPlan({acquired, sources, keyedFamily,
  captureStartedAt, captureCompletedAt, sourcePlan, managedRun, sourceHost,
  deferCatalogs = false}, keyedDefinition) {
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
  const run = JSON.parse(runDefinition.wire);
  const {plan, retention, retentionDependencies} = buildLocalPublicationPlan({
    control, admission, runDefinition, invocation, observation,
    compiledPlanCid: compiledPlan.identity,
    programDefinitionCid: moon.clientProgramEffectDefinitionCid(prepared),
    inputRelationCids: [...new Set([
      moon.clientProgramCapturedSourceLogicalCid(sources[0].captured.identity),
      keyedFamily.evidence.logicalRelationCid])],
    sourceEvidence: [sources[0].sourceEvidence, keyedFamily.evidence.source],
    authorityScopeCid, namespaceId, storeAuthorityCid,
    dataPolicyCid: JSON.parse(observation.wire).data_policy_cid,
    createdAt: run.created_at, now, retainUntil: run.valid_until,
    resultCount: moon.clientProgramEffectCompilationResultNames(compilation).length,
    moon, effectCompilation: compilation, preparedEffect: prepared,
    outputLimits: checkedPublicationLimitValues(moon.clientProgramInstalledEffectPublicationLimits(
      managedRun, prepared, acquired.requestIdentity, sourcePlan, hostResultStorePolicy.maxObjectBytes)),
    retentionSelection: acquired.selectRetention?.(),
    originalRetention: (managedRun === undefined ? undefined : control.issueInstalledEffectInitialRetention(managedRun, prepared,
      acquired.requestIdentity, sourcePlan, JSON.parse(observation.wire).data_policy_cid, acquired.selectRetention(), limits))});
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
  captureStartedAt, captureCompletedAt, content, sourcePlan, managedRun, sourceHost, deferCatalogs = false}) {
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
        ...checked((deferCatalogs ? moon.clientProgramEffectPublicationPolicyBodiesDeferredCatalog : moon.clientProgramEffectPublicationPolicyBodies)(prepared,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth)).map(body =>
          Object.freeze({kind: runtimeField(body, 0), cid: runtimeField(body, 1), wire: runtimeField(body, 2)})),
      ])}),
      sourceLocalInvocation: acquiredEvidence.invocation,
      runInvocation: invocation, observation})});
}

// Retain the actual upstream Unit semantics before opening the first Model.
// The existing group owns this cache and its dispatch borrow through cleanup;
// no complete Model/Run observation or physical publication is claimed here.
export function prepareAcquiredEffectSourceUnits({acquired, sources, sourcePlan, managedRun, modelUnits, deferCatalogs = false}) {
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
  const retention = control.issueInstalledEffectInitialRetention(managedRun, acquired.prepared,
    acquired.requestIdentity, sourcePlan, policy, acquired.selectRetention(), limits);
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
  captureStartedAt, captureCompletedAt, issuedModel, modelOriginal, modelOriginals = modelOriginal === undefined ? [] : [modelOriginal], modelEvidence = [], keyedSource, sourcePlan, managedRun, sourceHost, sourceUnitsOriginal, deferCatalogs = false}) {
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
    retentionSelection: acquired.selectRetention?.(), originalRetention: sourceUnitsOriginal?.retention ??
      (managedRun === undefined ? undefined : control.issueInstalledEffectInitialRetention(managedRun, prepared,
      acquired.requestIdentity, sourcePlan, dataPolicyCid, acquired.selectRetention(), limits))});
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
          captured.checkedSource.sourceDataPolicyCid, limits);
        acquiredEvidenceByUnit[unit] = control.issueCheckedAcquiredEffectEvidence(
          prepared, captured.capture.source(), captured.identity,
          captured.requirement, captured.logicalInput, sourceEvidence[slot],
          authorityScopeCid, captured.checkedSource.sourceDataPolicyCid,
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
        ...checked((deferCatalogs ? moon.clientProgramEffectPublicationPolicyBodiesDeferredCatalog : moon.clientProgramEffectPublicationPolicyBodies)(prepared,
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
  captureStartedAt, captureCompletedAt, keyedSource, signal, sourcePlan, managedRun, sourceHost, sourceUnitsOriginal, fundingOperation = operation, current, retainBinding, deferCatalogs = false}) {
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
    authoringContextOriginal: restored.authoringContextOriginal,
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
  sourceEvidence = [], outputLimits = localOutputLimits, managedPublication, assertCurrent}) {
  if (managedPublication !== undefined) {
    managedProgramPublicationCurrent(moon, preparedProgram, admitted, managedPublication,
      managedPublication.value, managedPublication.request);
    if (typeof assertCurrent !== 'function') throw new TypeError('OriginalProgramRetentionCurrentRequired');
  }
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
  const originalRetention = managedPublication === undefined ? undefined :
    managedProgramInitialRetention(moon, control, preparedProgram, admitted, managedPublication,
      observation.data_policy_cid, now, assertCurrent);
  const plan = localPublicationPlan({control, originalRetention, admission: admitted.admission,
    runDefinition: admitted.runDefinition, invocation: issued.invocation,
    observation: issued.observation, compiledPlanCid: admitted.compiledPlan.identity,
    programDefinitionCid: moon.clientProgramDefinitionCid(preparedProgram),
    inputRelationCids: [JSON.parse(input.wire).logical_relation_cid], sourceEvidence,
    authorityScopeCid, namespaceId, storeAuthorityCid,
    dataPolicyCid: observation.data_policy_cid, createdAt: admitted.createdAt, now,
    resultCount: moon.clientProgramResultCount(preparedProgram), outputLimits,
    compiled: admitted.compiled, preparedProgram, authoringContextOriginal: admitted.authoringContextOriginal});
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
  storeAuthorityCid, now, managedPublication, assertCurrent}) {
  if (managedPublication !== undefined) {
    managedProgramPublicationCurrent(moon, preparedProgram, admitted, managedPublication,
      managedPublication.value, managedPublication.request);
    if (typeof assertCurrent !== 'function') throw new TypeError('OriginalProgramRetentionCurrentRequired');
  }
  control.checkClientCompiledRunOwner(admitted.compiled, preparedProgram);
  if (admitted.kind !== 'infer' || !Array.isArray(modelEvidence)) {
    throw new TypeError('InvalidInferPublicationAdmission');
  }
  const issued = operation.bindIssuedInvocation(control, {
    compiled: admitted.compiled, runDefinition: admitted.runDefinition,
    issued: issuance});
  try {
    const observation = JSON.parse(issued.observation.wire);
    const originalRetention = managedPublication === undefined ? undefined :
      managedProgramInitialRetention(moon, control, preparedProgram, admitted, managedPublication,
        observation.data_policy_cid, now, assertCurrent);
    const plan = localPublicationPlan({control, originalRetention,
      admission: admitted.admission, runDefinition: admitted.runDefinition,
      invocation: issued.invocation, observation: issued.observation,
      compiledPlanCid: admitted.compiledPlan.identity,
      programDefinitionCid: moon.clientProgramDefinitionCid(preparedProgram),
      inputRelationCids: observation.captured_input_artifact_cids,
      sourceEvidence, modelEvidence, authorityScopeCid, namespaceId,
      storeAuthorityCid, dataPolicyCid: observation.data_policy_cid,
      createdAt: admitted.createdAt, now,
      resultCount: moon.clientProgramResultCount(preparedProgram),
      compiled: admitted.compiled, preparedProgram, authoringContextOriginal: admitted.authoringContextOriginal});
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
