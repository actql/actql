import * as owner from './dist/client_values_host_abi.js';

const environments = new WeakMap();
const preparations = new WeakMap();
const compilations = new WeakMap();
const requests = new WeakMap();
const admissions = new WeakMap();
const definitions = new WeakMap();
const publicationContracts = new WeakMap();
const runEvidences = new WeakMap();
const resultOccurrences = new WeakMap();
const capturedSnapshots = new WeakMap();
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

export function compiledPlanCid(compilation) {
  const {value} = requireHandle(compilations, compilation);
  return owner.clientValuesHostCompiledPlanCid(value);
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

export function resultSchema(prepared, compilation) {
  const compiled = requireHandle(compilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const facts = checked(owner.clientValuesHostResultSchema(
    requireHandle(preparations, prepared)),
  'RunHostResultSchemaRejected');
  if (!Array.isArray(facts) || facts.length < 2 ||
      !facts.every(value => typeof value === 'string') ||
      !/^sha256:[0-9a-f]{64}$/u.test(facts[0])) {
    throw new Error('InvalidRunHostResultSchema');
  }
  const fields = Object.freeze(facts.slice(2));
  if (Object.keys(JSON.parse(facts[1])).join('\0') !==
      fields.join('\0')) {
    throw new Error('InvalidRunHostResultSchema');
  }
  return Object.freeze({cid: facts[0], wire: facts[1], fields});
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

export function issueSourceFreeRunDefinition(prepared, compilation,
  admission, scopeId, runId, createdAt, validUntil) {
  const compiled = requireHandle(compilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  if ([scopeId, runId, createdAt, validUntil]
    .some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostDefinition');
  }
  const value = checked(owner.clientValuesHostIssueSourceFreeRunDefinition(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    scopeId, runId, createdAt, validUntil),
  'RunHostSourceFreeDefinitionRejected');
  return handle(definitions, value, 'run-definition');
}

export function privateRunDefinition(definition) {
  const value = requireHandle(definitions, definition);
  return Object.freeze({
    wire: owner.clientValuesHostRunDefinitionWire(value),
    cid: owner.clientValuesHostRunDefinitionCid(value),
  });
}

// The caller must retain the checked admission and the current physical
// observation. A state wire is a projection, never Run or read authority.
export function issueUnpublishedRunStateWire(prepared, compilation,
  admission, definition, observedAt, dispatchReserved,
  preDispatchFailureConfirmed) {
  const compiled = requireHandle(compilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  if (typeof observedAt !== 'string' ||
      typeof dispatchReserved !== 'boolean' ||
      typeof preDispatchFailureConfirmed !== 'boolean') {
    throw new TypeError('InvalidRunHostStateObservation');
  }
  checkRunBinding(prepared, admission, definition);
  const wire = owner.clientValuesHostIssueUnpublishedRunStateWire(
    requireHandle(definitions, definition), compiled.value, observedAt,
    dispatchReserved, preDispatchFailureConfirmed);
  if (typeof wire !== 'string') {
    throw Object.assign(new Error('RunHostStateProjectionRejected'),
      {code: 'RunHostStateProjectionRejected'});
  }
  return wire;
}

export function issueSucceededRunStateWire(prepared, compilation,
  admission, definition, observedAt, observations) {
  const compiled = requireHandle(compilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  if (typeof observedAt !== 'string' || !Array.isArray(observations) ||
      !observations.every(value => value !== null &&
        typeof value === 'object' &&
        ['name', 'state', 'reason', 'observedAt'].every(key =>
          typeof value[key] === 'string'))) {
    throw new TypeError('InvalidRunHostStateObservation');
  }
  checkRunBinding(prepared, admission, definition);
  const wire = owner.clientValuesHostIssueSucceededRunStateWire(
    requireHandle(definitions, definition), compiled.value, observedAt,
    observations.map(value => value.name),
    observations.map(value => value.state),
    observations.map(value => value.reason),
    observations.map(value => value.observedAt));
  if (typeof wire !== 'string') {
    throw Object.assign(new Error('RunHostStateProjectionRejected'),
      {code: 'RunHostStateProjectionRejected'});
  }
  return wire;
}

export function resultReadAvailability(manifest, resultName, retention,
  observedAt) {
  if (typeof resultName !== 'string' || typeof observedAt !== 'string') {
    throw new TypeError('InvalidRunHostAvailabilityObservation');
  }
  return checked(owner.clientValuesHostResultReadAvailability(
    publicationToken(manifest), resultName, publicationToken(retention),
    observedAt), 'RunHostAvailabilityRejected');
}

// The common publication owner selects and checks every listed binding.
// CIDs returned here identify physical custody; they grant no read access.
export function projectCommittedResultRead(index, manifest, resultName,
  bindings) {
  if (typeof resultName !== 'string' || !Array.isArray(bindings)) {
    throw new TypeError('InvalidRunHostResultSelection');
  }
  const wire = owner.clientValuesHostProjectCommittedResultReadWire(
    publicationToken(index), publicationToken(manifest), resultName,
    publicationItems(bindings));
  if (typeof wire !== 'string') {
    throw Object.assign(new Error('RunHostResultSelectionRejected'),
      {code: 'RunHostResultSelectionRejected'});
  }
  const value = JSON.parse(wire);
  const cid = value => typeof value === 'string' &&
    /^sha256:[0-9a-f]{64}$/u.test(value);
  if (value === null || typeof value !== 'object' ||
      !['codec_contract_cid', 'durable_result_binding_cid',
        'effective_retention_policy_cid', 'logical_result_cid',
        'material_generation_cid', 'ordering_evidence_cid',
        'result_artifact_cid', 'result_definition_cid',
        'result_schema_cid', 'store_authority_cid'].every(key =>
        cid(value[key])) ||
      typeof value.physical_sha256 !== 'string' ||
      !/^[0-9a-f]{64}$/u.test(value.physical_sha256) ||
      value.result_name !== resultName ||
      !Array.isArray(value.result_fields) ||
      !value.result_fields.every(field => typeof field === 'string') ||
      !Number.isSafeInteger(value.row_count) || value.row_count < 0 ||
      !Number.isSafeInteger(value.byte_count) || value.byte_count < 0) {
    throw new Error('RunHostResultSelectionInvalid');
  }
  return Object.freeze({resultName: value.result_name,
    resultArtifactCid: value.result_artifact_cid,
    resultDefinitionCid: value.result_definition_cid,
    logicalResultCid: value.logical_result_cid,
    resultSchemaCid: value.result_schema_cid,
    orderingEvidenceCid: value.ordering_evidence_cid,
    effectiveRetentionPolicyCid: value.effective_retention_policy_cid,
    durableResultBindingCid: value.durable_result_binding_cid,
    materialGenerationCid: value.material_generation_cid,
    storeAuthorityCid: value.store_authority_cid,
    codecContractCid: value.codec_contract_cid,
    resultFields: Object.freeze([...value.result_fields]),
    rowCount: value.row_count, byteCount: value.byte_count,
    physicalSha256: value.physical_sha256});
}

export function admitRunDefinition(wire) {
  if (typeof wire !== 'string') throw new TypeError('InvalidRunHostDefinition');
  const value = checked(owner.clientValuesHostAdmitRunDefinition(wire),
    'RunHostDefinitionRejected');
  return handle(definitions, value, 'run-definition');
}

export function admitSourceFreeRunDefinition(prepared, compilation,
  admission, wire) {
  const compiled = requireHandle(compilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  if (typeof wire !== 'string') throw new TypeError('InvalidRunHostDefinition');
  const value = checked(owner.clientValuesHostAdmitSourceFreeRunDefinition(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    wire), 'RunHostSourceFreeAdmissionRejected');
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

export function issueSourceFreeInvocation(prepared, compilation, admission,
  definition, dataPolicyCid, limits) {
  if (typeof dataPolicyCid !== 'string') {
    throw new TypeError('InvalidRunHostDataPolicy');
  }
  const compiled = requireHandle(compilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  checkRunBinding(prepared, admission, definition);
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const facts = checked(owner.clientValuesHostIssueSourceFreeInvocation(
    compiled.value, dataPolicyCid, maxWireBytes, maxNodes, maxDepth),
  'RunHostInvocationRejected');
  if (!Array.isArray(facts) || facts.length !== 4 ||
      !facts.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostInvocationProjection');
  }
  const observation = admitRunEvidenceValue('observation_set', facts[1],
    limits);
  const invocation = admitPublicationContract('run_invocation', facts[3],
    limits);
  if (observation.cid !== facts[0] || invocation.cid !== facts[2]) {
    throw new Error('InvalidRunHostInvocationProjection');
  }
  return Object.freeze({observation, invocation});
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

function runEvidence(value) {
  const token = handle(runEvidences, value, 'run-evidence');
  return Object.freeze({token,
    cid: owner.clientValuesHostRunEvidenceValueIdentity(value),
    wire: owner.clientValuesHostRunEvidenceValueWire(value)});
}

export function admitRunEvidenceValue(name, wire, limits) {
  if (typeof name !== 'string' || typeof wire !== 'string') {
    throw new TypeError('InvalidRunHostEvidence');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return runEvidence(checked(owner.clientValuesHostAdmitRunEvidenceValue(
    name, wire, maxWireBytes, maxNodes, maxDepth),
  'RunHostEvidenceRejected'));
}

export function sealRunEvidenceValue(name, bodyWire, limits) {
  if (typeof name !== 'string' || typeof bodyWire !== 'string') {
    throw new TypeError('InvalidRunHostEvidence');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return runEvidence(checked(owner.clientValuesHostSealRunEvidenceValue(
    name, bodyWire, maxWireBytes, maxNodes, maxDepth),
  'RunHostEvidenceRejected'));
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

export function projectPublicationSnapshot(record, index) {
  if (index === null || typeof index !== 'object' ||
      Array.isArray(index) ||
      !['absent', 'unknown', 'committed'].includes(index.kind) ||
      Object.keys(index).sort().join('\0') !==
        (index.kind === 'committed' ? 'entry\0kind' : 'kind')) {
    throw new TypeError('InvalidRunHostIndexObservation');
  }
  const mode = index.kind === 'absent' ? 0 :
    index.kind === 'unknown' ? 1 : 2;
  const facts = checked(owner.clientValuesHostProjectPublicationSnapshot(
    record === undefined ? undefined : publicationToken(record), mode,
    mode === 2 ? publicationToken(index.entry) : undefined),
  'RunHostPublicationSnapshotRejected');
  if (!Array.isArray(facts) || facts.length !== 2 ||
      !facts.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostPublicationSnapshot');
  }
  return Object.freeze({state: facts[0],
    evidenceCid: facts[1] || undefined});
}

export function publicationIndexScopeKey(ref, limits) {
  if (ref === null || typeof ref !== 'object' || Array.isArray(ref) ||
      Object.keys(ref).sort().join('\0') !==
        'authorityScopeCid\0runDefinitionCid\0tenantId' ||
      !['tenantId', 'authorityScopeCid', 'runDefinitionCid']
        .every(key => typeof ref[key] === 'string')) {
    throw new TypeError('InvalidRunHostPublicationIndexScope');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return checked(owner.clientValuesHostPublicationIndexScopeKey(
    ref.tenantId, ref.authorityScopeCid, ref.runDefinitionCid,
    maxWireBytes, maxNodes, maxDepth),
  'RunHostPublicationIndexScopeRejected');
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
  return resultOccurrence(value);
}

function resultOccurrence(value) {
  const token = handle(resultOccurrences, value, 'result-occurrence');
  return Object.freeze({token,
    derivation: publicationContract(
      owner.clientValuesHostResultOccurrenceDerivation(value)),
    ordering: publicationContract(
      owner.clientValuesHostResultOccurrenceOrdering(value))});
}

export function issueCheckedValuesResultOccurrenceEvidence(prepared,
  compilation, definition, facts, limits) {
  if (facts === null || typeof facts !== 'object' ||
      Object.keys(facts).sort().join('\0') !==
        ['logicalValueCid', 'resultSchemaCid', 'scopeCid',
          'effectiveDataPolicyCid', 'issuerId', 'authorityScopeCid']
          .sort().join('\0') ||
      Object.values(facts).some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostCheckedResultEvidence');
  }
  const compiled = requireHandle(compilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const value = checked(
    owner.clientValuesHostIssueCheckedValuesResultOccurrenceEvidence(
      requireHandle(preparations, prepared), compiled.value,
      publicationToken(definition), facts.logicalValueCid,
      facts.resultSchemaCid, facts.scopeCid,
      facts.effectiveDataPolicyCid, facts.issuerId,
      facts.authorityScopeCid, maxWireBytes, maxNodes, maxDepth),
    'RunHostCheckedResultEvidenceRejected');
  return resultOccurrence(value);
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

function publicationItems(values) {
  if (!Array.isArray(values)) throw new TypeError('InvalidRunHostInventory');
  return values.map(publicationToken);
}

export function issuePublicationRequest(runDefinition, definitions, facts,
  limits) {
  if (facts === null || typeof facts !== 'object' ||
      ['tenantId', 'authorityScopeCid', 'publicationPolicyCid',
        'publicationTargetCid', 'requestedAt'].some(key =>
        typeof facts[key] !== 'string')) {
    throw new TypeError('InvalidRunHostPublicationRequest');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(
    owner.clientValuesHostIssuePublicationRequest(
      publicationToken(runDefinition), publicationItems(definitions),
      facts.tenantId, facts.authorityScopeCid,
      facts.publicationPolicyCid, facts.publicationTargetCid,
      facts.requestedAt, maxWireBytes, maxNodes, maxDepth),
    'RunHostPublicationRequestRejected'));
}

export function issuePublicationAttempt(request, runDefinition, facts,
  limits) {
  if (facts === null || typeof facts !== 'object' ||
      ['attemptId', 'fenceCid', 'startedAt'].some(key =>
        typeof facts[key] !== 'string') ||
      facts.externalIdempotencyKey !== undefined &&
        typeof facts.externalIdempotencyKey !== 'string') {
    throw new TypeError('InvalidRunHostPublicationAttempt');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(
    owner.clientValuesHostIssuePublicationAttempt(
      publicationToken(request), publicationToken(runDefinition),
      facts.attemptId, facts.fenceCid, facts.externalIdempotencyKey,
      facts.startedAt, maxWireBytes, maxNodes, maxDepth),
    'RunHostPublicationAttemptRejected'));
}

export function issuePublicIndexEntry(runDefinition, invocation, manifest,
  receipt, capturedRun, durableBindings, request, attempt, committedAt,
  limits) {
  if (typeof committedAt !== 'string') {
    throw new TypeError('InvalidRunHostPublicIndexEntry');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(owner.clientValuesHostIssuePublicIndexEntry(
    publicationToken(runDefinition), publicationToken(invocation),
    publicationToken(manifest), publicationToken(receipt),
    publicationToken(capturedRun), publicationItems(durableBindings),
    publicationToken(request), publicationToken(attempt), committedAt,
    maxWireBytes, maxNodes, maxDepth), 'RunHostPublicIndexEntryRejected'));
}

export function validateEffectFreePublicationCommit(evidence, request,
  attempt, indexEntry, limits) {
  if (evidence === null || typeof evidence !== 'object' ||
      !Array.isArray(evidence.definitions) ||
      !Array.isArray(evidence.artifacts) ||
      !Array.isArray(evidence.derivations) ||
      !Array.isArray(evidence.orderings) ||
      !Array.isArray(evidence.retentions) ||
      !Array.isArray(evidence.durableBindings)) {
    throw new TypeError('InvalidRunHostPublicationCommit');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  checked(owner.clientValuesHostValidateEffectFreePublicationCommit(
    publicationToken(evidence.runDefinition),
    publicationToken(evidence.invocation),
    publicationItems(evidence.definitions),
    publicationItems(evidence.artifacts),
    publicationItems(evidence.derivations),
    publicationItems(evidence.orderings),
    publicationItems(evidence.retentions),
    publicationItems(evidence.durableBindings),
    publicationToken(evidence.manifest),
    publicationToken(evidence.receipt),
    publicationToken(evidence.capturedRun),
    publicationToken(request), publicationToken(attempt),
    publicationToken(indexEntry), maxWireBytes, maxNodes, maxDepth),
  'RunHostPublicationCommitRejected');
}

export function issuePublicationRecord(attempt, previous, facts, limits) {
  if (facts === null || typeof facts !== 'object' ||
      typeof facts.state !== 'string' ||
      typeof facts.observedAt !== 'string' ||
      facts.failureCid !== undefined &&
        typeof facts.failureCid !== 'string' ||
      !Array.isArray(facts.cleanupOwnerCids) ||
      !facts.cleanupOwnerCids.every(value => typeof value === 'string') ||
      typeof facts.uncommittedConfirmed !== 'boolean') {
    throw new TypeError('InvalidRunHostPublicationRecord');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(owner.clientValuesHostIssuePublicationRecord(
    publicationToken(attempt), previous === undefined ? undefined :
      publicationToken(previous), facts.state, facts.observedAt,
    facts.publicIndexEntry === undefined ? undefined :
      publicationToken(facts.publicIndexEntry), facts.failureCid,
    facts.cleanupOwnerCids, facts.uncommittedConfirmed,
    maxWireBytes, maxNodes, maxDepth), 'RunHostPublicationRecordRejected'));
}

function evidenceItems(values) {
  if (!Array.isArray(values)) {
    throw new TypeError('InvalidRunHostEvidenceInventory');
  }
  return values.map(value => requireHandle(runEvidences, value?.token));
}

export function issueEffectFreeRunReceipt(admission, runDefinition,
  invocation, observation, definitions, artifacts, manifest,
  normalizationJournal, facts, limits) {
  if (facts === null || typeof facts !== 'object' ||
      !Array.isArray(facts.bindingNames) ||
      !facts.bindingNames.every(value => typeof value === 'string') ||
      !Array.isArray(facts.bindingDigests) ||
      !facts.bindingDigests.every(value => typeof value === 'string') ||
      !Array.isArray(facts.barrierAttemptReceiptCids) ||
      !facts.barrierAttemptReceiptCids.every(value =>
        typeof value === 'string')) {
    throw new TypeError('InvalidRunHostReceiptFacts');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(
    owner.clientValuesHostIssueEffectFreeRunReceipt(
      requireHandle(admissions, admission).value,
      publicationToken(runDefinition), publicationToken(invocation),
      requireHandle(runEvidences, observation?.token),
      publicationItems(definitions), publicationItems(artifacts),
      publicationToken(manifest),
      requireHandle(runEvidences, normalizationJournal?.token),
      facts.bindingNames, facts.bindingDigests,
      evidenceItems(facts.sourceEvidence),
      evidenceItems(facts.modelEvidence),
      facts.barrierAttemptReceiptCids,
      maxWireBytes, maxNodes, maxDepth),
    'RunHostReceiptRejected'));
}

export function admitCapturedResultSnapshot(definition, artifact, rowsWire,
  fields, limits) {
  if (typeof rowsWire !== 'string' || !Array.isArray(fields) ||
      !fields.every(value => typeof value === 'string')) {
    throw new TypeError('InvalidRunHostCapturedRows');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const snapshot = checked(owner.clientValuesHostAdmitCapturedResultSnapshot(
    publicationToken(definition), publicationToken(artifact), rowsWire,
    fields, maxWireBytes, maxNodes, maxDepth),
  'RunHostCapturedRowsRejected');
  return handle(capturedSnapshots, snapshot, 'captured-result-snapshot');
}

export function issueSourceFreeCapturedRun(runDefinition, invocation,
  definitions, artifacts, manifest, receipt, snapshots, authoring, models,
  limits) {
  if (!Array.isArray(snapshots)) {
    throw new TypeError('InvalidRunHostCapturedInventory');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(
    owner.clientValuesHostIssueSourceFreeCapturedRun(
      publicationToken(runDefinition), publicationToken(invocation),
      publicationItems(definitions), publicationItems(artifacts),
      publicationToken(manifest), publicationToken(receipt),
      snapshots.map(value => requireHandle(capturedSnapshots, value)),
      requireHandle(runEvidences, authoring?.token), evidenceItems(models),
      maxWireBytes, maxNodes, maxDepth),
    'RunHostCapturedRunRejected'));
}

// The portable publication service consumes this shape. Each view keeps its
// MoonBit handle in this instance; wire bytes and CIDs alone grant no access.
const deliveryViews = new WeakMap();
const accessProgress = new WeakMap();
const deliverySerializers = new WeakMap();
const durableRowFrames = new WeakMap();

function deliveryCall(method, ...args) {
  try { return owner[method](...args); }
  catch (cause) {
    throw Object.assign(new Error('RunHostDeliveryRejected', {cause}),
      {code: 'RunHostDeliveryRejected'});
  }
}

function deliveryResult(method, ...args) {
  return checked(deliveryCall(method, ...args), 'RunHostDeliveryRejected');
}

function deliveryView(contract) {
  const value = publicationToken(contract);
  const view = Object.freeze({
    name: owner.clientValuesHostPublicationContractName(value),
    identityField:
      owner.clientValuesHostPublicationContractIdentityField(value),
    identity: contract.cid, wire: contract.wire,
  });
  deliveryViews.set(view, contract);
  return view;
}

function deliveryToken(view) {
  return publicationToken(deliveryContract(view));
}

function deliveryContract(view) {
  const contract = deliveryViews.get(view);
  if (contract === undefined) throw new TypeError('ForeignRunHostDelivery');
  return contract;
}

function issuedDelivery(method, ...args) {
  return deliveryView(publicationContract(deliveryResult(method, ...args)));
}

// This is a semantic port for the existing common Result access service.
// The Host still supplies current authorization, trusted time, Store and sink.
export function openResultDeliveryControl() {
  const limitsOf = limits => {
    const value = publicationLimits(limits);
    return [value.maxWireBytes, value.maxNodes, value.maxDepth];
  };
  const progressToken = progress => requireHandle(accessProgress, progress);
  const mark = (method, progress, value) =>
    deliveryCall(method, progressToken(progress), value);
  return Object.freeze({
    admit(name, wire, limits) {
      return deliveryView(admitPublicationContract(name, wire, limits));
    },
    beginResultAccessProgress() {
      return handle(accessProgress,
        owner.clientValuesHostBeginResultAccessProgress(),
        'result-access-progress');
    },
    resultAccessProgressAction(progress) {
      return owner.clientValuesHostResultAccessProgressAction(
        progressToken(progress));
    },
    recordResultAccessRequestAuthorization(progress, value) {
      return mark('clientValuesHostRecordResultAccessRequestAuthorization',
        progress, value);
    },
    recordResultAccessResolution(progress, value) {
      return mark('clientValuesHostRecordResultAccessResolution',
        progress, value);
    },
    recordResultAccessInitialAvailability(progress, value) {
      return mark('clientValuesHostRecordResultAccessInitialAvailability',
        progress, value);
    },
    recordResultAccessReadAdmission(progress, value) {
      return mark('clientValuesHostRecordResultAccessReadAdmission',
        progress, value);
    },
    recordResultAccessGrant(progress, value) {
      return mark('clientValuesHostRecordResultAccessGrant', progress, value);
    },
    resultReadRetentionPolicyCid(manifest, resultName) {
      return deliveryResult('clientValuesHostResultReadRetentionPolicyCid',
        deliveryToken(manifest), resultName);
    },
    resultReadDefinitionCid(manifest, resultName) {
      return deliveryResult('clientValuesHostResultReadDefinitionCid',
        deliveryToken(manifest), resultName);
    },
    resultReadAvailability(manifest, resultName, retention, observedAt) {
      return resultReadAvailability(deliveryContract(manifest), resultName,
        deliveryContract(retention), observedAt);
    },
    resultReadExtendedAvailability(manifest, resultName, retention,
      extension, observedAt) {
      return deliveryResult('clientValuesHostResultReadExtendedAvailability',
        deliveryToken(manifest), resultName, deliveryToken(retention),
        deliveryToken(extension), observedAt);
    },
    resultRetentionClockContractCid(retention) {
      return deliveryResult('clientValuesHostResultRetentionClockContractCid',
        deliveryToken(retention));
    },
    issueResultReadGrant(index, manifest, grant, limits) {
      const bounds = limitsOf(limits);
      return issuedDelivery('clientValuesHostIssueResultReadGrant',
        deliveryToken(index), deliveryToken(manifest),
        grant.resultNames, grant.formats, grant.principalId, grant.purpose,
        grant.dataCeilingCid, grant.maxBytes, grant.maxUses,
        grant.expiresAt, grant.authorizationContextCid,
        grant.egressAdmissionCid, ...bounds);
    },
    resultReadGrantValidAt(grant, observedAt) {
      return owner.clientValuesHostResultReadGrantValidAt(
        deliveryToken(grant), observedAt);
    },
    resultReadGrantAllowsBytes(grant, count) {
      return owner.clientValuesHostResultReadGrantAllowsBytes(
        deliveryToken(grant), count);
    },
    issueDeliveryAttempt(index, manifest, grant, attempt, limits) {
      return issuedDelivery('clientValuesHostIssueDeliveryAttempt',
        deliveryToken(index), deliveryToken(manifest), deliveryToken(grant),
        attempt.resultName, attempt.format, attempt.attemptId,
        attempt.requestedAt, ...limitsOf(limits));
    },
    deliveryResultDefinitionCid(manifest, attempt) {
      return deliveryResult('clientValuesHostDeliveryResultDefinitionCid',
        deliveryToken(manifest), deliveryToken(attempt));
    },
    issueResultDeliveryReceipt(index, manifest, grant, attempt,
      delivered, limits) {
      return issuedDelivery('clientValuesHostIssueResultDeliveryReceipt',
        deliveryToken(index), deliveryToken(manifest), deliveryToken(grant),
        deliveryToken(attempt), delivered.byteCount, delivered.sha256,
        ...limitsOf(limits));
    },
    issueDeliveryRecord(attempt, previous, update, limits) {
      return issuedDelivery('clientValuesHostIssueDeliveryRecord',
        deliveryToken(attempt), previous === undefined ? undefined :
          deliveryToken(previous), update.state,
        update.confirmedByteCount, update.exposure,
        update.possibleUnconfirmedMaxBytes, update.deliveredSha256,
        update.receipt === undefined ? undefined :
          deliveryToken(update.receipt), update.failureCid,
        update.observedAt, update.cleanupOwnerCids, ...limitsOf(limits));
    },
    existingDeliveryAttemptAction(record) {
      return owner.clientValuesHostExistingDeliveryAttemptAction(
        record === undefined ? undefined : deliveryToken(record));
    },
    deliveryFailureTerminalAction(observed) {
      return owner.clientValuesHostDeliveryFailureTerminalAction(observed);
    },
    deliveryRecordRetryAction(next, count) {
      return owner.clientValuesHostDeliveryRecordRetryAction(next, count);
    },
    deliveryTransition(previous, next) {
      return owner.clientValuesHostDeliveryRecordTransition(
        previous === undefined ? undefined : deliveryToken(previous),
        deliveryToken(next));
    },
    deliverySuccessValid(attempt, receipt, record) {
      return owner.clientValuesHostDeliverySuccessValid(
        deliveryToken(attempt), deliveryToken(receipt),
        deliveryToken(record));
    },
    trustedClockNotBefore(previous, observedAt) {
      return owner.clientValuesHostTrustedClockNotBefore(previous, observedAt);
    },
    prepareDeliveryGrantUsageClaim(grant, existingWire, attempt, limits) {
      const claim = deliveryResult(
        'clientValuesHostPrepareDeliveryGrantUsageClaim',
        deliveryToken(grant), existingWire, deliveryToken(attempt),
        ...limitsOf(limits));
      return Object.freeze({
        wire: owner.clientValuesHostDeliveryGrantUsageClaimWire(claim),
        newlyClaimed:
          owner.clientValuesHostDeliveryGrantUsageClaimIsNew(claim),
      });
    },
    prepareDurableResultRowFrames(bounds) {
      const frames = deliveryResult(
        'clientValuesHostPrepareDurableResultRowFrames',
        bounds.maxBytes, bounds.maxRows, bounds.maxRowBytes,
        bounds.maxDepth, bounds.maxFrameBytes);
      return handle(durableRowFrames, frames, 'durable-row-frames');
    },
    feedDurableResultRowFrames(frames, chunk) {
      return deliveryResult('clientValuesHostFeedDurableResultRowFrames',
        requireHandle(durableRowFrames, frames), chunk);
    },
    finishDurableResultRowFrames(frames) {
      const values = deliveryResult('clientValuesHostFinishDurableResultRowFrames',
        requireHandle(durableRowFrames, frames));
      return Object.freeze({bytes: values[0], rows: values[1]});
    },
    cancelDurableResultRowFrames(frames) {
      return deliveryCall('clientValuesHostCancelDurableResultRowFrames',
        requireHandle(durableRowFrames, frames));
    },
    prepareResultDeliverySerializer(format, schemaWire, fields, limits) {
      const serializer = deliveryResult(
        'clientValuesHostPrepareResultDeliverySerializer',
        format, schemaWire, fields, ...limitsOf(limits));
      return handle(deliverySerializers, serializer, 'result-serializer');
    },
    beginResultDelivery(serializer) {
      return deliveryResult('clientValuesHostBeginResultDelivery',
        requireHandle(deliverySerializers, serializer));
    },
    nextResultDeliveryRow(serializer, rowWire) {
      return deliveryResult('clientValuesHostNextResultDeliveryRow',
        requireHandle(deliverySerializers, serializer), rowWire);
    },
    finishResultDelivery(serializer) {
      return deliveryResult('clientValuesHostFinishResultDelivery',
        requireHandle(deliverySerializers, serializer));
    },
  });
}
