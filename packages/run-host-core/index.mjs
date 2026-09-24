import * as owner from './dist/client_values_host_abi.js';

const environments = new WeakMap();
const preparations = new WeakMap();
const compilations = new WeakMap();
const requests = new WeakMap();
const admissions = new WeakMap();
const definitions = new WeakMap();
const publicationContracts = new WeakMap();
const resultOccurrences = new WeakMap();
const profileKeys = new Set(['textTime', 'veca', 'rela', 'sga', 'tea',
  'calendar', 'textRank']);

function checked(result, code) {
  if (result?.$tag === 1) return result._0;
  if (result?.$tag === 0) {
    throw Object.assign(new Error(code, {cause: result._0}), {code});
  }
  throw Object.assign(new Error('InvalidRunHostOwnerResult'),
    {code: 'InvalidRunHostOwnerResult'});
}

function handle(map, value, kind) {
  const token = Object.freeze({kind});
  map.set(token, value);
  return token;
}

function requireHandle(map, token) {
  const value = map.get(token);
  if (value === undefined) throw new TypeError('ForeignRunHostHandle');
  return value;
}

export function admitEnvironment(body, evidenceBundleCid, profiles) {
  if (typeof body !== 'string' || typeof evidenceBundleCid !== 'string' ||
      profiles === null || typeof profiles !== 'object' ||
      Array.isArray(profiles) || Object.entries(profiles).some(([key, value]) =>
        !profileKeys.has(key) || typeof value !== 'boolean')) {
    throw new TypeError('InvalidRunHostEnvironment');
  }
  const value = owner.clientValuesHostEnvironment(body, evidenceBundleCid,
    profiles.textTime === true, profiles.veca === true,
    profiles.rela === true, profiles.sga === true,
    profiles.tea === true, profiles.calendar === true,
    profiles.textRank === true);
  if (value === undefined) {
    throw Object.assign(new Error('RunHostEnvironmentRejected'),
      {code: 'RunHostEnvironmentRejected'});
  }
  return handle(environments, value, 'check-environment');
}

export function prepare(document, format, environment, parametersWire) {
  if (typeof document !== 'string' || !['json', 'yaml'].includes(format) ||
      parametersWire !== undefined && typeof parametersWire !== 'string') {
    throw new TypeError('InvalidRunHostPreparation');
  }
  const value = checked(owner.clientValuesHostPrepare(document, format,
    requireHandle(environments, environment), parametersWire),
  'RunHostPreparationRejected');
  return handle(preparations, value, 'prepared-program');
}

export function compileValues(prepared) {
  const value = checked(owner.clientValuesHostCompile(
    requireHandle(preparations, prepared)), 'RunHostCompilationRejected');
  return handle(compilations, {value, prepared}, 'values-compilation');
}

export function privateCompilationWires(compilation) {
  const {value} = requireHandle(compilations, compilation);
  return Object.freeze({
    executablePlan: owner.clientValuesHostPlanWire(value),
    factManifest: owner.clientValuesHostFactManifestWire(value),
    boundTemplate: owner.clientValuesHostTemplateWire(value),
    compiledPlan: owner.clientValuesHostCompiledPlanWire(value),
  });
}

export function executionShape(compilation) {
  const {value} = requireHandle(compilations, compilation);
  return Object.freeze({
    planNodeId: owner.clientValuesHostPlanNodeId(value),
    outputContractCid: owner.clientValuesHostOutputContractCid(value),
    resultNames: Object.freeze([...owner.clientValuesHostResultNames(value)]),
  });
}

export function resultDefinitions(prepared, compilation) {
  const compiled = requireHandle(compilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const fields = checked(owner.clientValuesHostResultDefinitions(
    requireHandle(preparations, prepared), compiled.value),
  'RunHostResultInventoryRejected');
  const names = owner.clientValuesHostResultNames(compiled.value);
  if (!Array.isArray(fields) || fields.length !== names.length * 3 ||
      !fields.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostResultInventory');
  }
  return Object.freeze(names.map((name, index) => {
    if (fields[index * 3] !== name) {
      throw new Error('InvalidRunHostResultInventory');
    }
    return Object.freeze({name, cid: fields[index * 3 + 1],
      wire: fields[index * 3 + 2]});
  }));
}

// The Host must establish scope and admitted input intent before calling this
// pure identity operation. The returned handle is not a Run or a grant.
export function prepareRequest(prepared, authorityScopeCid, requestId,
  admittedInputIntentCid) {
  if ([authorityScopeCid, requestId, admittedInputIntentCid]
    .some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostRequest');
  }
  const value = checked(owner.clientValuesHostRequestIdentity(
    requireHandle(preparations, prepared), authorityScopeCid, requestId,
    admittedInputIntentCid), 'RunHostRequestRejected');
  return handle(requests, value, 'request-identity');
}

export function prepareSourceFreeRequest(prepared, compilation,
  authorityScopeCid, requestId) {
  if (typeof authorityScopeCid !== 'string' || typeof requestId !== 'string') {
    throw new TypeError('InvalidRunHostRequest');
  }
  const {prepared: compiledFrom} = requireHandle(compilations, compilation);
  if (compiledFrom !== prepared) throw new TypeError('ForeignRunHostCompilation');
  const value = checked(owner.clientValuesHostSourceFreeRequestIdentity(
    requireHandle(preparations, prepared), authorityScopeCid, requestId),
  'RunHostRequestRejected');
  return handle(requests, value, 'request-identity');
}

export function requestFields(request) {
  const value = requireHandle(requests, request);
  return Object.freeze({
    authorityScopeCid: owner.clientValuesHostRequestAuthorityScopeCid(value),
    requestId: owner.clientValuesHostRequestCallerId(value),
    logicalRequestScopeCid: owner.clientValuesHostRequestScopeCid(value),
    intentFingerprintCid: owner.clientValuesHostRequestIntentCid(value),
    programDefinitionCid: owner.clientValuesHostRequestProgramCid(value),
    parameterValuesCid: owner.clientValuesHostRequestParametersCid(value),
    callerInputIntentCid: owner.clientValuesHostRequestInputCid(value),
  });
}

const requestKeys = ['authorityScopeCid', 'requestId',
  'logicalRequestScopeCid', 'intentFingerprintCid', 'programDefinitionCid',
  'parameterValuesCid', 'callerInputIntentCid'];

export function admitRequestFields(fields) {
  if (fields === null || typeof fields !== 'object' || Array.isArray(fields) ||
      Object.keys(fields).sort().join('\0') !==
        [...requestKeys].sort().join('\0') ||
      requestKeys.some(key => typeof fields[key] !== 'string')) {
    throw new TypeError('InvalidRunHostRequestRecord');
  }
  const value = checked(owner.clientValuesHostAdmitRequestIdentity(
    fields.authorityScopeCid, fields.requestId,
    fields.programDefinitionCid, fields.parameterValuesCid,
    fields.callerInputIntentCid, fields.logicalRequestScopeCid,
    fields.intentFingerprintCid), 'RunHostRequestRecordRejected');
  return handle(requests, value, 'request-identity');
}

export function admitSourceFreeRequestFields(prepared, compilation, fields) {
  if (fields === null || typeof fields !== 'object' || Array.isArray(fields) ||
      Object.keys(fields).sort().join('\0') !==
        [...requestKeys].sort().join('\0') ||
      requestKeys.some(key => typeof fields[key] !== 'string')) {
    throw new TypeError('InvalidRunHostRequestRecord');
  }
  const value = checked(owner.clientValuesHostAdmitSourceFreeRequestIdentity(
    fields.authorityScopeCid, fields.requestId,
    fields.programDefinitionCid, fields.parameterValuesCid,
    fields.callerInputIntentCid, fields.logicalRequestScopeCid,
    fields.intentFingerprintCid), 'RunHostRequestRecordRejected');
  const current = prepareSourceFreeRequest(prepared, compilation,
    fields.authorityScopeCid, fields.requestId);
  if (owner.clientValuesHostRequestRelation(
    requireHandle(requests, current), value) !== 1) {
    throw Object.assign(new Error('RunHostRequestRecordRejected'),
      {code: 'RunHostRequestRecordRejected'});
  }
  return handle(requests, value, 'request-identity');
}

export function requestRelation(requested, retained) {
  const relation = owner.clientValuesHostRequestRelation(
    requireHandle(requests, requested), requireHandle(requests, retained));
  switch (relation) {
    case 0: return 'different_request';
    case 1: return 'same_request';
    case 2: return 'changed_intent';
    default: throw new Error('InvalidRunHostRequestRelation');
  }
}

export function admitRun(prepared, compilation, preparedInvocationWire,
  authorizationWire) {
  if (typeof preparedInvocationWire !== 'string' ||
      typeof authorizationWire !== 'string') {
    throw new TypeError('InvalidRunHostEvidence');
  }
  const compiled = requireHandle(compilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const value = checked(owner.clientValuesHostAdmitRun(
    requireHandle(preparations, prepared),
    compiled.value,
    preparedInvocationWire, authorizationWire),
  'RunHostAdmissionRejected');
  return handle(admissions, {value, prepared}, 'run-admission');
}

// Host authorization must precede this call. These owner-issued wires bind
// the selected policy context to the exact checked Values compilation.
export function issueAllowedRun(prepared, compilation, {
  executionContextCid, hostPolicyCid, expiresAt,
}) {
  if ([executionContextCid, hostPolicyCid, expiresAt]
    .some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostEvidence');
  }
  const compiled = requireHandle(compilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const issued = checked(owner.clientValuesHostIssueAllowedRun(
    requireHandle(preparations, prepared), compiled.value,
    executionContextCid, hostPolicyCid, expiresAt),
  'RunHostAdmissionRejected');
  return Object.freeze({
    admission: handle(admissions, {
      value: owner.clientValuesHostAllowedRunAdmission(issued), prepared,
    }, 'run-admission'),
    preparedInvocationWire:
      owner.clientValuesHostAllowedRunPreparedWire(issued),
    authorizationWire:
      owner.clientValuesHostAllowedRunAuthorizationWire(issued),
  });
}

export function issueRunDefinition(admission, scopeId, runId,
  inputArtifactSetCid, createdAt, validUntil) {
  if ([scopeId, runId, inputArtifactSetCid, createdAt, validUntil]
    .some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostDefinition');
  }
  const value = checked(owner.clientValuesHostIssueRunDefinition(
    requireHandle(admissions, admission).value, scopeId, runId,
    inputArtifactSetCid, createdAt, validUntil),
  'RunHostDefinitionRejected');
  return handle(definitions, value, 'run-definition');
}

export function privateRunDefinition(definition) {
  const value = requireHandle(definitions, definition);
  return Object.freeze({
    wire: owner.clientValuesHostRunDefinitionWire(value),
    cid: owner.clientValuesHostRunDefinitionCid(value),
  });
}

export function admitRunDefinition(wire) {
  if (typeof wire !== 'string') throw new TypeError('InvalidRunHostDefinition');
  const value = checked(owner.clientValuesHostAdmitRunDefinition(wire),
    'RunHostDefinitionRejected');
  return handle(definitions, value, 'run-definition');
}

export function prepareRunStart(requested, retained, definition,
  retainedRunDefinitionCid, dispatchReserved, currentAuthorization) {
  if (typeof retainedRunDefinitionCid !== 'string' ||
      typeof dispatchReserved !== 'boolean' ||
      typeof currentAuthorization !== 'boolean') {
    throw new TypeError('InvalidRunHostStart');
  }
  const action = checked(owner.clientValuesHostPrepareRunStart(
    requireHandle(requests, requested), requireHandle(requests, retained),
    requireHandle(definitions, definition), retainedRunDefinitionCid,
    dispatchReserved, currentAuthorization), 'RunHostStartRejected');
  switch (action) {
    case 0: return 'reserve_dispatch';
    case 1: return 'reconcile_reserved_dispatch';
    default: throw new Error('InvalidRunHostStartAction');
  }
}

export function checkRunBinding(prepared, admission, definition) {
  const admitted = requireHandle(admissions, admission);
  if (admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostAdmission');
  }
  checked(owner.clientValuesHostCheckRunBinding(
    requireHandle(preparations, prepared), admitted.value,
    requireHandle(definitions, definition)), 'RunHostBindingRejected');
}

const siteSelectionKeys = ['taskAttempt', 'dispatchId', 'siteKey',
  'siteGeneration', 'runtimeBundleCid', 'connectorRegistration',
  'connectorRevision', 'strategyRevision', 'obligationsCid', 'budgetCid',
  'evidenceIssuerCapabilityCid', 'grantCid'];

// The current Host authorization and Site policy decision precede issuance.
// The returned canonical wire is identity material, not a Site credential.
export function issueSourceFreeDispatch(prepared, compilation, admission,
  definition, request, selection) {
  if (selection === null || typeof selection !== 'object' ||
      Array.isArray(selection) ||
      Object.keys(selection).sort().join('\0') !==
        [...siteSelectionKeys].sort().join('\0') ||
      !Number.isSafeInteger(selection.taskAttempt) ||
      !Number.isSafeInteger(selection.siteGeneration) ||
      siteSelectionKeys.slice(1).filter(key => key !== 'siteGeneration')
        .some(key => typeof selection[key] !== 'string')) {
    throw new TypeError('InvalidRunHostSiteSelection');
  }
  const compiled = requireHandle(compilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const dispatch = checked(owner.clientValuesHostPrepareDispatch(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    requireHandle(definitions, definition), requireHandle(requests, request),
    selection.taskAttempt, selection.dispatchId, selection.siteKey,
    selection.siteGeneration, selection.runtimeBundleCid,
    selection.connectorRegistration, selection.connectorRevision,
    selection.strategyRevision, selection.obligationsCid,
    selection.budgetCid, selection.evidenceIssuerCapabilityCid,
    selection.grantCid), 'RunHostDispatchRejected');
  return Object.freeze({cid: owner.clientValuesHostDispatchCid(dispatch),
    wire: checked(owner.clientValuesHostDispatchWire(dispatch),
      'RunHostDispatchRejected')});
}

function publicationLimits(limits) {
  if (limits === null || typeof limits !== 'object' ||
      !['maxWireBytes', 'maxNodes', 'maxDepth'].every(key =>
        Number.isSafeInteger(limits[key]) && limits[key] > 0 &&
        limits[key] <= 2147483647)) {
    throw new TypeError('InvalidRunHostPublicationLimits');
  }
  return limits;
}

function publicationContract(value) {
  const token = handle(publicationContracts, value, 'publication-contract');
  return Object.freeze({token,
    cid: owner.clientValuesHostPublicationContractIdentity(value),
    wire: owner.clientValuesHostPublicationContractWire(value)});
}

// Canonical admission and chain decisions belong to the portable owner.
// A contract handle is in-process only and conveys no publication authority.
export function admitPublicationContract(name, wire, limits) {
  if (typeof name !== 'string' || typeof wire !== 'string') {
    throw new TypeError('InvalidRunHostPublicationContract');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const value = checked(owner.clientValuesHostAdmitPublicationContract(
    name, wire, maxWireBytes, maxNodes, maxDepth),
  'RunHostPublicationContractRejected');
  return publicationContract(value);
}

function publicationToken(contract) {
  return requireHandle(publicationContracts, contract?.token);
}

function nonnegativeCount(value) {
  if (!Number.isSafeInteger(value) || value < 0 || value > 2147483647) {
    throw new TypeError('InvalidRunHostPublicationCount');
  }
  return value;
}

export function issueResultOccurrenceEvidence(definition, facts, limits) {
  if (facts === null || typeof facts !== 'object' ||
      !['logicalValueCid', 'resultSchemaCid', 'computationContractCid',
        'scopeCid', 'effectiveDataPolicyCid', 'issuerId',
        'authorityScopeCid'].every(key => typeof facts[key] === 'string') ||
      !Array.isArray(facts.inputRelationCids) ||
      !facts.inputRelationCids.every(value => typeof value === 'string')) {
    throw new TypeError('InvalidRunHostResultEvidence');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const value = checked(owner.clientValuesHostIssueResultOccurrenceEvidence(
    publicationToken(definition), facts.logicalValueCid,
    facts.resultSchemaCid, facts.computationContractCid,
    facts.inputRelationCids, facts.scopeCid,
    facts.effectiveDataPolicyCid, facts.issuerId,
    facts.authorityScopeCid, maxWireBytes, maxNodes, maxDepth),
  'RunHostResultEvidenceRejected');
  const token = handle(resultOccurrences, value, 'result-occurrence');
  return Object.freeze({token,
    derivation: publicationContract(
      owner.clientValuesHostResultOccurrenceDerivation(value)),
    ordering: publicationContract(
      owner.clientValuesHostResultOccurrenceOrdering(value))});
}

export function issueCompleteResultArtifact(definition, invocation,
  evidence, retention, actualRowCount, limits) {
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(
    owner.clientValuesHostIssueCompleteResultArtifact(
      publicationToken(definition), publicationToken(invocation),
      requireHandle(resultOccurrences, evidence?.token),
      publicationToken(retention), nonnegativeCount(actualRowCount),
      maxWireBytes, maxNodes, maxDepth),
    'RunHostResultArtifactRejected'));
}

export function issueDurableResultBinding(runDefinition, definition,
  invocation, artifact, ordering, retention, physical, limits) {
  if (physical === null || typeof physical !== 'object' ||
      !['codecContractCid', 'resultSchemaWire', 'materialGenerationCid',
        'storeAuthorityCid', 'physicalSha256'].every(key =>
        typeof physical[key] === 'string') ||
      !Array.isArray(physical.resultFields) ||
      !physical.resultFields.every(value => typeof value === 'string')) {
    throw new TypeError('InvalidRunHostDurableBinding');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(
    owner.clientValuesHostIssueDurableResultBinding(
      publicationToken(runDefinition), publicationToken(definition),
      publicationToken(invocation), publicationToken(artifact),
      publicationToken(ordering), publicationToken(retention),
      physical.codecContractCid, physical.resultFields,
      physical.resultSchemaWire, physical.materialGenerationCid,
      physical.storeAuthorityCid, nonnegativeCount(physical.rowCount),
      nonnegativeCount(physical.byteCount), physical.physicalSha256,
      maxWireBytes, maxNodes, maxDepth),
    'RunHostDurableBindingRejected'));
}

export function inspectCanonicalResultRows(rowsWire, fields, limits) {
  if (typeof rowsWire !== 'string' || !Array.isArray(fields) ||
      !fields.every(value => typeof value === 'string')) {
    throw new TypeError('InvalidRunHostResultRows');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const result = checked(owner.clientValuesHostInspectCanonicalResultRows(
    rowsWire, fields, maxWireBytes, maxNodes, maxDepth),
  'RunHostResultRowsRejected');
  if (!Array.isArray(result) || result.length !== 2 ||
      typeof result[0] !== 'string' ||
      !/^sha256:[0-9a-f]{64}$/u.test(result[0]) ||
      typeof result[1] !== 'string' ||
      !/^(0|[1-9][0-9]*)$/u.test(result[1])) {
    throw new Error('InvalidRunHostResultRowsProjection');
  }
  const rowCount = Number(result[1]);
  if (!Number.isSafeInteger(rowCount)) {
    throw new Error('InvalidRunHostResultRowsProjection');
  }
  return Object.freeze({logicalRelationCid: result[0], rowCount});
}

export function issueResultManifest(runDefinition, invocation,
  definitions, artifacts, limits) {
  if (!Array.isArray(definitions) || !Array.isArray(artifacts)) {
    throw new TypeError('InvalidRunHostPublicationChain');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(owner.clientValuesHostIssueResultManifest(
    publicationToken(runDefinition), publicationToken(invocation),
    definitions.map(publicationToken), artifacts.map(publicationToken),
    maxWireBytes, maxNodes, maxDepth), 'RunHostResultManifestRejected'));
}

export function validatePublicationChain(runDefinition, invocation,
  definitions, artifacts, manifest, limits) {
  if (!Array.isArray(definitions) || !Array.isArray(artifacts)) {
    throw new TypeError('InvalidRunHostPublicationChain');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  checked(owner.clientValuesHostValidatePublicationChain(
    publicationToken(runDefinition), publicationToken(invocation),
    definitions.map(publicationToken), artifacts.map(publicationToken),
    publicationToken(manifest), maxWireBytes, maxNodes, maxDepth),
  'RunHostPublicationChainRejected');
}

export function validatePublicationRecordTransition(previous, next,
  uncommittedConfirmed) {
  if (typeof uncommittedConfirmed !== 'boolean') {
    throw new TypeError('InvalidRunHostPublicationTransition');
  }
  checked(owner.clientValuesHostValidatePublicationRecordTransition(
    previous === undefined ? undefined : publicationToken(previous),
    publicationToken(next), uncommittedConfirmed),
  'RunHostPublicationTransitionRejected');
}
