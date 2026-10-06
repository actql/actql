import * as owner from './dist/client_values_host_abi.js';

const retainedInputEdges = new WeakMap();
const retainedInputProducers = new WeakMap();
const retainedInputIntents = new WeakMap();
const retainedInputPlans = new WeakMap();
const retainedInputResults = new WeakMap();
const retainedTaskInputs = new WeakMap();
import {publicationAction} from './publication-action.mjs';

const environments = new WeakMap();
const preparations = new WeakMap();
const compilations = new WeakMap();
const taskCompilations = new WeakMap();
const requests = new WeakMap();
const admissions = new WeakMap();
const definitions = new WeakMap();
const publicationContracts = new WeakMap();
const runEvidences = new WeakMap();
const resultOccurrences = new WeakMap();
const capturedSnapshots = new WeakMap();
const materialHolds = new WeakMap();
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

/** Shared Result-generation hold decisions; physical CAS stays in the Host. */
export function beginResultMaterialHolds(bindingCid, materialGenerationCid) {
  return handle(materialHolds, deliveryResult(
    'clientValuesHostBeginResultMaterialHolds', bindingCid,
    materialGenerationCid), 'result-material-holds');
}

export function admitResultMaterialHolds(wire) {
  if (typeof wire !== 'string') throw new TypeError('InvalidMaterialHoldsWire');
  return handle(materialHolds, deliveryResult(
    'clientValuesHostAdmitResultMaterialHolds', wire),
  'result-material-holds');
}

export function resultMaterialHoldsWire(value) {
  return deliveryResult('clientValuesHostResultMaterialHoldsWire',
    requireHandle(materialHolds, value));
}

export function resultMaterialHoldsFacts(value) {
  const ownerValue = requireHandle(materialHolds, value);
  return Object.freeze({
    bindingCid: owner.clientValuesHostResultMaterialHoldsBinding(ownerValue),
    materialGenerationCid:
      owner.clientValuesHostResultMaterialHoldsGeneration(ownerValue),
    revision: owner.clientValuesHostResultMaterialHoldsRevision(ownerValue),
    reclaimable:
      owner.clientValuesHostResultMaterialHoldsReclaimable(ownerValue),
  });
}

export function prepareResultMaterialHoldsStep(value, operation, identity) {
  if (!['add_consumer', 'release_consumer', 'begin_reader',
    'end_reader', 'stop_readers'].includes(operation) ||
    typeof identity !== 'string') {
    throw new TypeError('InvalidMaterialHoldsStep');
  }
  return handle(materialHolds, deliveryResult(
    'clientValuesHostPrepareResultMaterialHoldsStep',
    requireHandle(materialHolds, value), operation, identity),
  'result-material-holds');
}

function checkedProfileSelection(profiles, error) {
  if (profiles === null || typeof profiles !== 'object' ||
      Array.isArray(profiles) || Object.entries(profiles).some(([key, value]) =>
        !profileKeys.has(key) || typeof value !== 'boolean')) {
    throw new TypeError(error);
  }
  return Object.freeze({
    textTime: profiles.textTime === true,
    veca: profiles.veca === true,
    rela: profiles.rela === true,
    sga: profiles.sga === true,
    tea: profiles.tea === true,
    calendar: profiles.calendar === true,
    textRank: profiles.textRank === true,
  });
}

/** Admit the existing profile contract and make omitted selections explicit. */
export function admitProfileSelection(profiles) {
  return checkedProfileSelection(profiles, 'InvalidRunHostProfileSelection');
}

export function admitEnvironment(body, evidenceBundleCid, profiles) {
  if (typeof body !== 'string' || typeof evidenceBundleCid !== 'string') {
    throw new TypeError('InvalidRunHostEnvironment');
  }
  const selected = checkedProfileSelection(profiles, 'InvalidRunHostEnvironment');
  const value = owner.clientValuesHostEnvironment(body, evidenceBundleCid,
    selected.textTime, selected.veca, selected.rela, selected.sga,
    selected.tea, selected.calendar, selected.textRank);
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

export function compileTasks(prepared) {
  const value = checked(owner.clientValuesHostCompileTasks(
    requireHandle(preparations, prepared)), 'RunHostTaskCompilationRejected');
  return handle(taskCompilations, {value, prepared}, 'task-compilation');
}

export function privateTaskCompilationWires(compilation) {
  const {value} = requireHandle(taskCompilations, compilation);
  return Object.freeze({
    executablePlan: owner.clientValuesHostTaskPlanWire(value),
    factManifest: owner.clientValuesHostTaskFactManifestWire(value),
    boundTemplate: owner.clientValuesHostTaskTemplateWire(value),
    compiledPlan: owner.clientValuesHostTaskCompiledPlanWire(value),
  });
}

export function taskResultNames(compilation) {
  const {value} = requireHandle(taskCompilations, compilation);
  return Object.freeze([...owner.clientValuesHostTaskResultNames(value)]);
}

export function taskExecutionShape(prepared, compilation) {
  const compiled = requireHandle(taskCompilations, compilation);
  if (compiled.prepared !== prepared) throw new TypeError('ForeignRunHostCompilation');
  const counts = owner.clientValuesHostTaskExecutionShape(requireHandle(preparations, prepared));
  if (!Array.isArray(counts) || counts.length !== 2 ||
      counts.some(value => !Number.isSafeInteger(value) || value < 0)) {
    throw new Error('InvalidRunHostTaskExecutionProjection');
  }
  return Object.freeze({taskCount: counts[0], acquisitionCount: counts[1]});
}

/** Dispatch keys from checked task fragments, excluding Result transforms. */
export function taskKeys(prepared, compilation) {
  const compiled = requireHandle(taskCompilations, compilation);
  if (compiled.prepared !== prepared) throw new TypeError('ForeignRunHostCompilation');
  const keys = checked(owner.clientValuesHostTaskKeys(requireHandle(preparations, prepared)),
    'RunHostTaskKeysRejected');
  if (!Array.isArray(keys) || keys.some(key => typeof key !== 'string') ||
      new Set(keys).size !== keys.length) throw new Error('InvalidRunHostTaskKeyProjection');
  return Object.freeze([...keys]);
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

export function taskResultDefinitions(prepared, compilation) {
  const compiled = requireHandle(taskCompilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const fields = checked(owner.clientValuesHostTaskResultDefinitions(
    requireHandle(preparations, prepared), compiled.value),
  'RunHostResultInventoryRejected');
  const names = owner.clientValuesHostTaskResultNames(compiled.value);
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

export function taskResultSchema(prepared, compilation, resultName) {
  const compiled = requireHandle(taskCompilations, compilation);
  if (compiled.prepared !== prepared || typeof resultName !== 'string') {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const names = owner.clientValuesHostTaskResultNames(compiled.value);
  const result = names.indexOf(resultName);
  if (result < 0) throw new RangeError('UnknownRunHostResult');
  const facts = checked(owner.clientValuesHostTaskResultSchema(
    requireHandle(preparations, prepared), result),
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

// A later provider capture is not a caller-supplied Run-start Artifact.
export function prepareTaskRequest(prepared, compilation,
  authorityScopeCid, requestId) {
  if (typeof authorityScopeCid !== 'string' || typeof requestId !== 'string') {
    throw new TypeError('InvalidRunHostRequest');
  }
  const compiled = requireHandle(taskCompilations, compilation);
  if (compiled.prepared !== prepared) throw new TypeError('ForeignRunHostCompilation');
  const value = checked(owner.clientValuesHostSourceFreeRequestIdentity(
    requireHandle(preparations, prepared), authorityScopeCid, requestId),
  'RunHostRequestRejected');
  return handle(requests, value, 'request-identity');
}

export function sourceEvidenceFacts(prepared, stage, sourceIndex) {
  if (![stage, sourceIndex].every(value => Number.isSafeInteger(value) &&
      value >= 0 && value <= 2147483647)) {
    throw new TypeError('InvalidRunHostSourceSelection');
  }
  const option = owner.clientValuesHostSourceEvidenceFacts(
    requireHandle(preparations, prepared), stage, sourceIndex);
  if (option?.$tag === 0) return undefined;
  if (option?.$tag !== 1) throw new Error('InvalidRunHostSourceEvidenceProjection');
  const facts = option._0;
  if (!Array.isArray(facts) || facts.length !== 6 ||
      facts.some(value => typeof value !== 'string')) {
    throw new Error('InvalidRunHostSourceEvidenceProjection');
  }
  return Object.freeze({sourceRef: facts[0], sourceContractCid: facts[1],
    carrierSchemaContractCid: facts[2], sourceDataPolicyCid: facts[3],
    dataClassification: facts[4], sourceViewContractCid: facts[5]});
}

export function taskInputBinding(prepared, task) {
  if (!Number.isSafeInteger(task) || task < 0 || task > 2147483647) {
    throw new TypeError('InvalidRunHostTaskSelection');
  }
  return checked(owner.clientValuesHostTaskInputBinding(
    requireHandle(preparations, prepared), task), 'RunHostTaskBindingRejected');
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

export function issueAllowedTaskRun(prepared, compilation, {
  executionContextCid, hostPolicyCid, expiresAt,
}) {
  if ([executionContextCid, hostPolicyCid, expiresAt]
    .some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostEvidence');
  }
  const compiled = requireHandle(taskCompilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const issued = checked(owner.clientValuesHostIssueAllowedTaskRun(
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

export function admitTaskRun(prepared, compilation,
  preparedInvocationWire, authorizationWire) {
  if ([preparedInvocationWire, authorizationWire]
    .some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostEvidence');
  }
  const compiled = requireHandle(taskCompilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const value = checked(owner.clientValuesHostAdmitTaskRun(
    requireHandle(preparations, prepared), compiled.value,
    preparedInvocationWire, authorizationWire),
  'RunHostAdmissionRejected');
  return handle(admissions, {value, prepared}, 'run-admission');
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

export function issueTaskRunDefinition(prepared, compilation,
  admission, scopeId, runId, createdAt, validUntil) {
  const compiled = requireHandle(taskCompilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  if ([scopeId, runId, createdAt, validUntil]
    .some(value => typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostDefinition');
  }
  const value = checked(owner.clientValuesHostIssueTaskRunDefinition(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    scopeId, runId, createdAt, validUntil),
  'RunHostTaskDefinitionRejected');
  return handle(definitions, value, 'run-definition');
}

export function admitTaskRunDefinition(prepared, compilation, admission,
  wire) {
  if (typeof wire !== 'string') throw new TypeError('InvalidRunHostDefinition');
  const compiled = requireHandle(taskCompilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const value = checked(owner.clientValuesHostAdmitTaskRunDefinition(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    wire), 'RunHostTaskDefinitionRejected');
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
  admission, definition, observedAt, observation) {
  const task = taskCompilations.has(compilation);
  const compiled = requireHandle(task ? taskCompilations : compilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const {dispatchReserved, preDispatchFailureConfirmed,
    cancelledBeforeStart = false, executionUnknown = false} =
    observation ?? {};
  if (typeof observedAt !== 'string' ||
      observation === null || typeof observation !== 'object' ||
      Array.isArray(observation) ||
      typeof dispatchReserved !== 'boolean' ||
      typeof preDispatchFailureConfirmed !== 'boolean' ||
      typeof cancelledBeforeStart !== 'boolean' ||
      typeof executionUnknown !== 'boolean') {
    throw new TypeError('InvalidRunHostStateObservation');
  }
  checkRunBinding(prepared, admission, definition);
  const issue = task ? owner.clientValuesHostIssueTaskUnpublishedRunStateWire
    : owner.clientValuesHostIssueUnpublishedRunStateWire;
  const wire = issue(
    requireHandle(definitions, definition), compiled.value, observedAt,
    dispatchReserved, preDispatchFailureConfirmed, cancelledBeforeStart,
    executionUnknown);
  if (typeof wire !== 'string') {
    throw Object.assign(new Error('RunHostStateProjectionRejected'),
      {code: 'RunHostStateProjectionRejected'});
  }
  return wire;
}

export function issueSucceededRunStateWire(prepared, compilation,
  admission, definition, observedAt, observations) {
  const task = taskCompilations.has(compilation);
  const compiled = requireHandle(task ? taskCompilations : compilations, compilation);
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
  const issue = task ? owner.clientValuesHostIssueTaskSucceededRunStateWire
    : owner.clientValuesHostIssueSucceededRunStateWire;
  const wire = issue(
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

export function describeCommittedResult(index, manifest, resultName,
  bindings, definition, schemaWire, format, limits) {
  const bounds = publicationLimits(limits);
  const wire = owner.clientValuesHostDescribeCommittedResult(
    publicationToken(index), publicationToken(manifest), resultName,
    publicationItems(bindings), publicationToken(definition), schemaWire,
    format, bounds.maxWireBytes, bounds.maxNodes, bounds.maxDepth);
  if (typeof wire !== 'string') {
    throw Object.assign(new Error('RunHostResultDescriptionRejected'),
      {code: 'RunHostResultDescriptionRejected'});
  }
  return JSON.parse(wire);
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

/** Project the original Run; this does not compile or issue authorization. */
export function issueSourceFreeRunMaterials(prepared, compilation, admission,
  definition, retained) {
  const compiled = requireHandle(compilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  validateRunMaterialsInput(retained);
  return checked(owner.clientValuesHostIssueSourceFreeRunMaterials(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    requireHandle(definitions, definition),
    requireHandle(environments, retained.environment),
    retained.environmentWire, retained.document, retained.parametersWire),
  'RunHostRunMaterialsRejected');
}

/** Project the original checked task Run; Source bindings stay at the Site. */
export function issueTaskRunMaterials(prepared, compilation, admission,
  definition, retained) {
  const compiled = requireHandle(taskCompilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  validateRunMaterialsInput(retained);
  return checked(owner.clientValuesHostIssueTaskRunMaterials(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    requireHandle(definitions, definition),
    requireHandle(environments, retained.environment),
    retained.environmentWire, retained.document, retained.parametersWire),
  'RunHostRunMaterialsRejected');
}

function validateRunMaterialsInput(retained) {
  if (retained === null || typeof retained !== 'object' ||
      Array.isArray(retained) || retained.format !== 'json' ||
      typeof retained.document !== 'string' ||
      typeof retained.environmentWire !== 'string' ||
      retained.parametersWire !== undefined &&
        typeof retained.parametersWire !== 'string' ||
      Object.keys(retained).some(key => !['format', 'document',
        'environment', 'environmentWire', 'parametersWire'].includes(key))) {
    throw new TypeError('InvalidRunHostRunMaterialsInput');
  }
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

export function issueSourceFreeTaskInvocation(prepared, compilation,
  admission, definition, dataPolicyCid, limits) {
  if (typeof dataPolicyCid !== 'string') {
    throw new TypeError('InvalidRunHostDataPolicy');
  }
  const compiled = requireHandle(taskCompilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  checkRunBinding(prepared, admission, definition);
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const facts = checked(owner.clientValuesHostIssueSourceFreeTaskInvocation(
    compiled.value, dataPolicyCid, maxWireBytes, maxNodes, maxDepth),
  'RunHostTaskInvocationRejected');
  if (!Array.isArray(facts) || facts.length !== 4 ||
      !facts.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostTaskInvocationProjection');
  }
  const observation = admitRunEvidenceValue('observation_set', facts[1],
    limits);
  const invocation = admitPublicationContract('run_invocation', facts[3],
    limits);
  if (observation.cid !== facts[0] || invocation.cid !== facts[2]) {
    throw new Error('InvalidRunHostTaskInvocationProjection');
  }
  return Object.freeze({observation, invocation});
}

// Source Evidence may enter an acquired task Run only when the admitted
// logical input, checked source, and current Host scope agree. The Host still
// owns authorization and the live capture; this identity grants neither.
export function admitCompletedSourceObservation({sourceEvidenceWire,
  inputLogicalWire, sourceRef, sourceContractCid, authorityScopeCid,
  effectiveDataPolicyCid,
  limits}) {
  if ([sourceEvidenceWire, inputLogicalWire, sourceRef,
    sourceContractCid, authorityScopeCid, effectiveDataPolicyCid].some(value =>
    typeof value !== 'string')) {
    throw new TypeError('InvalidRunHostSourceObservation');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return checked(owner.clientValuesHostAdmitCompletedSourceObservation(
    sourceEvidenceWire, inputLogicalWire, sourceRef, sourceContractCid,
    authorityScopeCid, effectiveDataPolicyCid, maxWireBytes, maxNodes,
    maxDepth),
  'RunHostSourceObservationRejected');
}

export function issueTaskInvocation(prepared, compilation, admission,
  definition, {sourceEvidenceWire, inputLogicalWire, sourceRef,
    sourceContractCid, authorityScopeCid, dataPolicyCid,
    captureStartedAt, captureCompletedAt}, limits) {
  const compiled = requireHandle(taskCompilations, compilation);
  if (compiled.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  checkRunBinding(prepared, admission, definition);
  if ([sourceEvidenceWire, inputLogicalWire, sourceRef, sourceContractCid,
    authorityScopeCid, dataPolicyCid, captureStartedAt, captureCompletedAt]
    .some(value => typeof value !== 'string') ||
    ![captureStartedAt, captureCompletedAt].every(value =>
      /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/u.test(value) &&
      Number.isFinite(Date.parse(value)) &&
      new Date(value).toISOString() === value) ||
    captureStartedAt > captureCompletedAt) {
    throw new TypeError('InvalidRunHostTaskObservation');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  const facts = checked(owner.clientValuesHostIssueTaskInvocation(
    requireHandle(preparations, prepared), compiled.value,
    requireHandle(admissions, admission).value,
    requireHandle(definitions, definition), sourceEvidenceWire,
    inputLogicalWire, sourceRef,
    sourceContractCid, authorityScopeCid, dataPolicyCid,
    captureStartedAt, captureCompletedAt, maxWireBytes, maxNodes,
    maxDepth), 'RunHostTaskInvocationRejected');
  if (!Array.isArray(facts) || facts.length !== 4 ||
      !facts.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostTaskInvocationProjection');
  }
  const observation = admitRunEvidenceValue('observation_set', facts[1],
    limits);
  const invocation = admitPublicationContract('run_invocation', facts[3],
    limits);
  if (observation.cid !== facts[0] || invocation.cid !== facts[2]) {
    throw new Error('InvalidRunHostTaskInvocationProjection');
  }
  return Object.freeze({observation, invocation});
}

const siteSelectionKeys = ['taskAttempt', 'dispatchId', 'siteKey',
  'siteGeneration', 'runtimeBundleCid', 'connectorRegistration',
  'connectorRevision', 'strategyRevision', 'obligationsCid', 'budgetCid',
  'evidenceIssuerCapabilityCid', 'grantCid'];

/** Checked topology only: no producer completion, holding or start authority. */
export function prepareRetainedTaskInputEdge(prepared, compilation, admission,
  definition, consumerTask, inputIndex) {
  if (![consumerTask, inputIndex].every(value => Number.isSafeInteger(value) &&
      value >= 0 && value <= 2147483647)) {
    throw new TypeError('InvalidRunHostRetainedInputEdge');
  }
  const compiled = requireHandle(taskCompilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const edge = checked(owner.clientValuesHostRetainedInputEdge(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    requireHandle(definitions, definition), consumerTask, inputIndex),
  'RunHostRetainedInputEdgeRejected');
  return handle(retainedInputEdges, edge, 'retained-input-edge');
}

/** Carrier port identity and physical schema identity remain distinct. */
export function retainedTaskInputEdgeFacts(edge) {
  const values = owner.clientValuesHostRetainedInputEdgeFacts(
    requireHandle(retainedInputEdges, edge));
  if (!Array.isArray(values) || values.length !== 9 ||
      !values.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostRetainedInputEdgeProjection');
  }
  const [runDefinitionCid, producerTaskKey, producerOutputPort,
    producerLogicalCid, carrierContractCid, consumerTaskKey,
    consumerLogicalCid, consumerInputPort, physicalSchemaCid] = values;
  return Object.freeze({runDefinitionCid, producerTaskKey, producerOutputPort,
    producerLogicalCid, carrierContractCid, consumerTaskKey,
    consumerLogicalCid, consumerInputPort, physicalSchemaCid});
}

/** The trusted Host must read its current durable Coordinator owner here. */
export function prepareRetainedInputProducer(edge, readCurrent) {
  const ownedEdge = requireHandle(retainedInputEdges, edge);
  if (typeof readCurrent !== 'function') {
    throw new TypeError('InvalidRunHostRetainedProducerCurrent');
  }
  const current = () => {
    const value = readCurrent();
    if (value === null || typeof value !== 'object' || Array.isArray(value) ||
        Object.keys(value).sort().join('\0') !== 'authority\0durableRecordWire' ||
        typeof value.authority !== 'string' ||
        typeof value.durableRecordWire !== 'string') {
      throw new TypeError('InvalidRunHostRetainedProducerCurrent');
    }
    return [value.authority, value.durableRecordWire];
  };
  const producer = checked(owner.clientValuesHostRetainedInputProducer(
    ownedEdge, current), 'RunHostRetainedProducerRejected');
  return handle(retainedInputProducers, producer, 'retained-input-producer');
}

export function retainedInputProducerAvailable(producer) {
  return owner.clientValuesHostRetainedInputProducerAvailable(
    requireHandle(retainedInputProducers, producer));
}

/** Historical canonical evidence; it grants no read, borrow or dispatch. */
export function retainedInputProducerFacts(producer) {
  const values = checked(owner.clientValuesHostRetainedInputProducerFacts(
    requireHandle(retainedInputProducers, producer)),
  'RunHostRetainedProducerRejected');
  if (!Array.isArray(values) || values.length !== 6 ||
      !values.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostRetainedProducerProjection');
  }
  const [dispatchCid, dispatchWire, evidenceCid, evidenceWire,
    subjectCid, subjectWire] = values;
  return Object.freeze({dispatch: Object.freeze({cid: dispatchCid, wire: dispatchWire}),
    evidence: Object.freeze({cid: evidenceCid, wire: evidenceWire}),
    subject: Object.freeze({cid: subjectCid, wire: subjectWire})});
}

const retainedPlanPolicyKeys = ['destinationGrantCid', 'routeCapabilityCid',
  'sourceGrantCid', 'transferAttempt', 'transferExpiresUnixMs', 'transferMaxBytes'];
const retainedPlanCurrentKeys = ['siteBindingCurrent', 'authority', 'nowUnixMs', 'authorized'];
const retainedPlanLimitKeys = ['maxChunks', 'maxManifestBytes', 'maxReferencedBytes'];
const retainedInt64Maximum = 9223372036854775807n;
const exactRetainedFields = (value, keys) => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const retainedWire = value => exactRetainedFields(value, ['cid', 'wire']) &&
  typeof value.cid === 'string' && typeof value.wire === 'string';

/** The checked producer supplies every edge and completion field. */
export function prepareRetainedInputIntent(producer, policy) {
  const owned = requireHandle(retainedInputProducers, producer);
  if (!exactRetainedFields(policy, retainedPlanPolicyKeys) ||
      retainedPlanPolicyKeys.slice(0, 4).some(key => typeof policy[key] !== 'string') ||
      ['transferExpiresUnixMs', 'transferMaxBytes'].some(key =>
        typeof policy[key] !== 'bigint' || policy[key] < 1n ||
        policy[key] > retainedInt64Maximum)) {
    throw new TypeError('InvalidRunHostRetainedInputPolicy');
  }
  const value = checked(owner.clientValuesHostPrepareRetainedInputIntent(owned,
    policy.destinationGrantCid, policy.routeCapabilityCid, policy.sourceGrantCid,
    policy.transferAttempt, policy.transferExpiresUnixMs, policy.transferMaxBytes),
  'RunHostRetainedInputIntentRejected');
  return handle(retainedInputIntents, {producer: owned, value}, 'retained-input-intent');
}

/** Restore original saved bytes, not another intent or refreshed lifetime. */
export function admitRetainedInputIntent(producer, saved) {
  const owned = requireHandle(retainedInputProducers, producer);
  if (!retainedWire(saved)) throw new TypeError('InvalidRunHostRetainedInputIntentWire');
  const value = checked(owner.clientValuesHostAdmitRetainedInputIntent(
    owned, saved.wire, saved.cid), 'RunHostRetainedInputIntentRejected');
  return handle(retainedInputIntents, {producer: owned, value}, 'retained-input-intent');
}

/** Historical projection only; it is not current delivery permission. */
export function retainedInputIntentFacts(intent) {
  const values = owner.clientValuesHostRetainedInputIntentFacts(
    requireHandle(retainedInputIntents, intent).value);
  if (!Array.isArray(values) || values.length !== 2 ||
      !values.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostRetainedInputIntentProjection');
  }
  return Object.freeze({cid: values[0], wire: values[1]});
}

/** Checked original poll envelope, before the Native physical manifest exists. */
export function retainedInputPlanEnvelope(intent) {
  const owned = requireHandle(retainedInputIntents, intent);
  return checked(owner.clientValuesHostRetainedInputPlanEnvelope(
    owned.producer, owned.value), 'RunHostRetainedInputIntentRejected');
}

/** Current trusted scope is required even when restoring a saved Native plan. */
export function admitRetainedInputPlan(intent, saved, current, limits) {
  const owned = requireHandle(retainedInputIntents, intent);
  if (!retainedWire(saved)) throw new TypeError('InvalidRunHostRetainedInputPlanWire');
  if (!exactRetainedFields(current, retainedPlanCurrentKeys) ||
      retainedPlanCurrentKeys.some(key => typeof current[key] !== 'function')) {
    throw new TypeError('InvalidRunHostRetainedPlanCurrent');
  }
  if (!exactRetainedFields(limits, retainedPlanLimitKeys) ||
      ['maxChunks', 'maxManifestBytes'].some(key =>
        !Number.isSafeInteger(limits[key]) || limits[key] < 1 || limits[key] > 2147483647) ||
      typeof limits.maxReferencedBytes !== 'bigint' || limits.maxReferencedBytes < 1n ||
      limits.maxReferencedBytes > retainedInt64Maximum) {
    throw new TypeError('InvalidRunHostRetainedPlanLimits');
  }
  // Capture ports, not their first successful answers. Every validation reads
  // current trusted state; changing an object's properties cannot swap ports.
  const {siteBindingCurrent, authority, nowUnixMs, authorized} = current;
  const booleanResult = (value, code) => {
    if (typeof value !== 'boolean') throw new TypeError(code);
    return value;
  };
  const value = checked(owner.clientValuesHostAdmitRetainedInputPlan(
    owned.producer, owned.value, saved.wire, saved.cid,
    (key, generation, bundle) => booleanResult(
      siteBindingCurrent(key, Number(generation), bundle), 'InvalidRunHostRetainedSiteCurrent'),
    () => {
      const value = authority();
      if (typeof value !== 'string') throw new TypeError('InvalidRunHostRetainedAuthority');
      return value;
    },
    () => {
      const value = nowUnixMs();
      if (typeof value !== 'bigint' || value < 0n || value > retainedInt64Maximum) {
        throw new TypeError('InvalidRunHostRetainedClock');
      }
      return value;
    },
    (dispatchCid, requestWire) => booleanResult(authorized(dispatchCid, requestWire),
      'InvalidRunHostRetainedAuthorization'),
    limits.maxChunks, limits.maxManifestBytes, limits.maxReferencedBytes),
  'RunHostRetainedInputPlanRejected');
  return handle(retainedInputPlans, value, 'retained-input-plan');
}

/** Revalidate after persistence and immediately before delivery. */
export function validateRetainedInputPlan(plan) {
  checked(owner.clientValuesHostValidateRetainedInputPlan(
    requireHandle(retainedInputPlans, plan)), 'RunHostRetainedInputPlanRejected');
}

/** Immutable originals only; no reservation, borrow, payload or start claim. */
export function retainedInputPlanFacts(plan) {
  const values = checked(owner.clientValuesHostRetainedInputPlanFacts(
    requireHandle(retainedInputPlans, plan)), 'RunHostRetainedInputPlanRejected');
  if (!Array.isArray(values) || values.length !== 6 ||
      !values.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostRetainedInputPlanProjection');
  }
  return Object.freeze({cid: values[0], wire: values[1],
    transfer: Object.freeze({cid: values[2], wire: values[3]}),
    manifest: Object.freeze({cid: values[4], wire: values[5]})});
}

/** Revalidate the original checked plan against live Owners before delivery. */
export function retainedInputTransferEnvelope(plan) {
  return checked(owner.clientValuesHostRetainedInputTransferEnvelope(
    requireHandle(retainedInputPlans, plan)), 'RunHostRetainedInputPlanRejected');
}

/** Historical committed receipt, never current custody or consumer authority. */
export function admitRetainedInputResult(plan, saved) {
  const owned = requireHandle(retainedInputPlans, plan);
  if (!retainedWire(saved)) throw new TypeError('InvalidRunHostRetainedInputResultWire');
  const value = checked(owner.clientValuesHostAdmitRetainedInputResult(
    owned, saved.wire, saved.cid), 'RunHostRetainedInputResultRejected');
  return handle(retainedInputResults, value, 'retained-input-result');
}

/** These immutable facts must be persisted and joined to current trusted Owners. */
export function retainedInputResultFacts(result) {
  const values = checked(owner.clientValuesHostRetainedInputResultFacts(
    requireHandle(retainedInputResults, result)), 'RunHostRetainedInputResultRejected');
  if (!Array.isArray(values) || values.length !== 7 ||
      !values.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostRetainedInputResultProjection');
  }
  return Object.freeze({cid: values[0], wire: values[1], planCid: values[2],
    transferReply: Object.freeze({requestCid: values[3], wire: values[4]}),
    receipt: Object.freeze({cid: values[5], wire: values[6]})});
}

const retainedCurrentKeys = ['readTransfer', 'siteBindingCurrent', 'authority',
  'nowUnixMs', 'authorized'];

/** Ports must query existing current owners, never the saved binding itself. */
export function prepareRetainedTaskInput(producer, receipt, destinationUseId,
  current, limits) {
  const owned = requireHandle(retainedInputProducers, producer);
  if (receipt === null || typeof receipt !== 'object' || Array.isArray(receipt) ||
      Object.keys(receipt).sort().join('\0') !== 'cid\0wire' ||
      typeof receipt.cid !== 'string' || typeof receipt.wire !== 'string' ||
      typeof destinationUseId !== 'string' || !destinationUseId ||
      current === null || typeof current !== 'object' || Array.isArray(current) ||
      Object.keys(current).sort().join('\0') !== [...retainedCurrentKeys].sort().join('\0') ||
      retainedCurrentKeys.some(key => typeof current[key] !== 'function')) {
    throw new TypeError('InvalidRunHostRetainedInputCurrent');
  }
  if (limits === null || typeof limits !== 'object' || Array.isArray(limits) ||
      Object.keys(limits).sort().join('\0') !==
        'maxBindingBytes\0maxChunks\0maxManifestBytes\0maxReferencedBytes' ||
      ['maxBindingBytes', 'maxChunks', 'maxManifestBytes'].some(key =>
        !Number.isSafeInteger(limits[key]) || limits[key] < 1 || limits[key] > 2147483647) ||
      typeof limits.maxReferencedBytes !== 'bigint' || limits.maxReferencedBytes < 1n ||
      limits.maxReferencedBytes > 9223372036854775807n) {
    throw new TypeError('InvalidRunHostRetainedInputLimits');
  }
  // Capture the installed functions so replacing properties cannot replace an
  // Owner port; each invocation still reads that Owner's current live state.
  const {readTransfer, siteBindingCurrent, authority, nowUnixMs, authorized} = current;
  const stringResult = (read, code) => () => {
    const value = read();
    if (typeof value !== 'string') throw new TypeError(code);
    return value;
  };
  const booleanResult = (value, code) => {
    if (typeof value !== 'boolean') throw new TypeError(code);
    return value;
  };
  const input = checked(owner.clientValuesHostPrepareRetainedTaskInput(owned,
    stringResult(readTransfer, 'InvalidRunHostRetainedTransferCurrent'),
    receipt.wire, receipt.cid, destinationUseId,
    (key, generation, bundle) => booleanResult(
      siteBindingCurrent(key, Number(generation), bundle),
      'InvalidRunHostRetainedSiteCurrent'),
    stringResult(authority, 'InvalidRunHostRetainedAuthority'),
    () => {
      const value = nowUnixMs();
      if (typeof value !== 'bigint' || value < 0n || value > 9223372036854775807n) {
        throw new TypeError('InvalidRunHostRetainedClock');
      }
      return value;
    },
    (dispatchCid, transferRequestWire) => booleanResult(
      authorized(dispatchCid, transferRequestWire),
      'InvalidRunHostRetainedAuthorization'),
    limits.maxChunks, limits.maxManifestBytes, limits.maxReferencedBytes,
    limits.maxBindingBytes), 'RunHostRetainedTaskInputRejected');
  return handle(retainedTaskInputs, input, 'retained-task-input');
}

/** Restore the exact saved binding against newly installed current owners. */
export function admitRetainedTaskInput(producer, saved, receipt,
  destinationUseId, current, limits) {
  if (saved === null || typeof saved !== 'object' || Array.isArray(saved) ||
      Object.keys(saved).sort().join('\0') !== 'cid\0wire' ||
      typeof saved.cid !== 'string' || typeof saved.wire !== 'string') {
    throw new TypeError('InvalidRunHostRetainedTaskInputWire');
  }
  const restored = prepareRetainedTaskInput(producer, receipt, destinationUseId,
    current, limits);
  const value = checked(owner.clientValuesHostAdmitRetainedTaskInput(
    requireHandle(retainedTaskInputs, restored), saved.wire, saved.cid),
  'RunHostRetainedTaskInputRejected');
  return handle(retainedTaskInputs, value, 'retained-task-input');
}

export function validateRetainedTaskInput(input) {
  checked(owner.clientValuesHostValidateRetainedTaskInput(
    requireHandle(retainedTaskInputs, input)), 'RunHostRetainedTaskInputRejected');
}

/** Historical wire grants no physical material access or start claim. */
export function retainedTaskInputFacts(input) {
  const values = owner.clientValuesHostRetainedTaskInputFacts(
    requireHandle(retainedTaskInputs, input));
  if (!Array.isArray(values) || values.length !== 2 ||
      !values.every(value => typeof value === 'string')) {
    throw new Error('InvalidRunHostRetainedTaskInputProjection');
  }
  return Object.freeze({cid: values[0], wire: values[1]});
}

export function issueRetainedTaskDispatch(prepared, compilation, admission,
  definition, request, task, selection, input) {
  if (!Number.isSafeInteger(task) || task < 0 || task > 2147483647 ||
      selection === null || typeof selection !== 'object' || Array.isArray(selection) ||
      Object.keys(selection).sort().join('\0') !== [...siteSelectionKeys].sort().join('\0') ||
      !Number.isSafeInteger(selection.taskAttempt) ||
      !Number.isSafeInteger(selection.siteGeneration) ||
      siteSelectionKeys.slice(1).filter(key => key !== 'siteGeneration')
        .some(key => typeof selection[key] !== 'string')) {
    throw new TypeError('InvalidRunHostSiteSelection');
  }
  const compiled = requireHandle(taskCompilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const dispatch = checked(owner.clientValuesHostPrepareRetainedTaskDispatch(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    requireHandle(definitions, definition), requireHandle(requests, request),
    task, selection.taskAttempt, selection.dispatchId, selection.siteKey,
    selection.siteGeneration, selection.runtimeBundleCid,
    selection.connectorRegistration, selection.connectorRevision,
    selection.strategyRevision, selection.obligationsCid, selection.budgetCid,
    selection.evidenceIssuerCapabilityCid, selection.grantCid,
    requireHandle(retainedTaskInputs, input)), 'RunHostRetainedTaskDispatchRejected');
  return Object.freeze({cid: owner.clientValuesHostDispatchCid(dispatch),
    wire: checked(owner.clientValuesHostDispatchWire(dispatch),
      'RunHostRetainedTaskDispatchRejected')});
}

export function issueTaskDispatch(prepared, compilation, admission,
  definition, request, task, selection) {
  if (!Number.isSafeInteger(task) || task < 0 || task > 2147483647 ||
      selection === null || typeof selection !== 'object' ||
      Array.isArray(selection) ||
      Object.keys(selection).sort().join('\0') !==
        [...siteSelectionKeys].sort().join('\0') ||
      !Number.isSafeInteger(selection.taskAttempt) ||
      !Number.isSafeInteger(selection.siteGeneration) ||
      siteSelectionKeys.slice(1).filter(key => key !== 'siteGeneration')
        .some(key => typeof selection[key] !== 'string')) {
    throw new TypeError('InvalidRunHostSiteSelection');
  }
  const compiled = requireHandle(taskCompilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  const dispatch = checked(owner.clientValuesHostPrepareTaskDispatch(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    requireHandle(definitions, definition), requireHandle(requests, request),
    task, selection.taskAttempt, selection.dispatchId, selection.siteKey,
    selection.siteGeneration, selection.runtimeBundleCid,
    selection.connectorRegistration, selection.connectorRevision,
    selection.strategyRevision, selection.obligationsCid,
    selection.budgetCid, selection.evidenceIssuerCapabilityCid,
    selection.grantCid), 'RunHostDispatchRejected');
  return Object.freeze({cid: owner.clientValuesHostDispatchCid(dispatch),
    wire: checked(owner.clientValuesHostDispatchWire(dispatch),
      'RunHostDispatchRejected')});
}

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
        'authorityScopeCid\0namespaceId\0runDefinitionCid' ||
      !['namespaceId', 'authorityScopeCid', 'runDefinitionCid']
        .every(key => typeof ref[key] === 'string')) {
    throw new TypeError('InvalidRunHostPublicationIndexScope');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return checked(owner.clientValuesHostPublicationIndexScopeKey(
    ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid,
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
      ['namespaceId', 'authorityScopeCid', 'publicationPolicyCid',
        'publicationTargetCid', 'requestedAt'].some(key =>
        typeof facts[key] !== 'string')) {
    throw new TypeError('InvalidRunHostPublicationRequest');
  }
  const {maxWireBytes, maxNodes, maxDepth} = publicationLimits(limits);
  return publicationContract(checked(
    owner.clientValuesHostIssuePublicationRequest(
      publicationToken(runDefinition), publicationItems(definitions),
      facts.namespaceId, facts.authorityScopeCid,
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
  return issueReadOnlyCapturedRun(runDefinition, invocation, definitions,
    artifacts, manifest, receipt, snapshots, authoring, models, limits);
}

// Read-only Sources, like Values, have no pending source-state advances.
// The same receipt and captured-computation owner validates the full chain.
export function issueReadOnlyCapturedRun(runDefinition, invocation,
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
    describeCommittedResult(index, manifest, resultName, bindings,
      definition, schemaWire, format, limits) {
      return describeCommittedResult(deliveryContract(index),
        deliveryContract(manifest), resultName,
        bindings.map(deliveryContract), deliveryContract(definition),
        schemaWire, format, limits);
    },
    resultMetadataRetentionState(retention, observedAt) {
      const value = owner.clientValuesHostResultMetadataRetentionState(
        deliveryToken(retention), observedAt);
      if (!['retained', 'delete_due'].includes(value)) {
        throw new Error('RunHostMetadataRetentionRejected');
      }
      return value;
    },
    issueManifestReadGrant(index, manifest, grant, limits) {
      return issuedDelivery('clientValuesHostIssueManifestReadGrant',
        deliveryToken(index), deliveryToken(manifest),
        grant.principalId, grant.purpose, grant.dataCeilingCid,
        grant.maxBytes, grant.maxUses, grant.expiresAt,
        grant.authorizationContextCid, ...limitsOf(limits));
    },
    manifestReadGrantValidAt(grant, at) {
      return deliveryCall('clientValuesHostManifestReadGrantValidAt',
        deliveryToken(grant), at);
    },
    manifestReadGrantAllowsBytes(grant, bytes) {
      return deliveryCall('clientValuesHostManifestReadGrantAllowsBytes',
        deliveryToken(grant), bytes);
    },
    admit(name, wire, limits) {
      return deliveryView(admitPublicationContract(name, wire, limits));
    },
    beginResultAccessProgress() {
      return handle(accessProgress,
        owner.clientValuesHostBeginResultAccessProgress(),
        'result-access-progress');
    },
    resultAccessProgressAction(progress) {
      return publicationAction('resultAccess',
        owner.clientValuesHostResultAccessProgressAction(progressToken(progress)));
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
      return publicationAction('existingDelivery',
        owner.clientValuesHostExistingDeliveryAttemptAction(
          record === undefined ? undefined : deliveryToken(record)));
    },
    deliveryFailureTerminalAction(observed) {
      return publicationAction('failureTerminal',
        owner.clientValuesHostDeliveryFailureTerminalAction(observed));
    },
    deliveryRecordRetryAction(next, count) {
      return publicationAction('recordRetry',
        owner.clientValuesHostDeliveryRecordRetryAction(next, count));
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

function admittedTaskProgress(prepared, compilation, admission, definition,
  authority, durableWires) {
  const compiled = requireHandle(taskCompilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  if (typeof authority !== 'string' || !Array.isArray(durableWires) ||
      durableWires.some(wire => typeof wire !== 'string')) {
    throw new TypeError('InvalidRunHostTaskProgress');
  }
  checkRunBinding(prepared, admission, definition);
  return checked(owner.clientValuesHostInspectTaskProgress(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    requireHandle(definitions, definition), authority, durableWires),
  'RunHostTaskProgressRejected');
}

function taskProgressSnapshot(value) {
  const scopes = owner.clientValuesHostTaskProgressScopes(value);
  const next = owner.clientValuesHostTaskProgressNext(value);
  return Object.freeze({
    nextTask: next < 0 ? undefined : next,
    executionComplete: owner.clientValuesHostTaskProgressExecutionComplete(value),
    cleanupComplete: owner.clientValuesHostTaskProgressCleanupComplete(value),
    resultTasks: Object.freeze(owner.clientValuesHostTaskProgressResultTasks(value)),
    tasks: Object.freeze(owner.clientValuesHostTaskProgressFields(value).map((row, index) =>
      Object.freeze({ordinal: Number(row[0]), taskKey: row[1], execution: row[2],
        cleanup: row[3], revision: Number(row[4]), dispatchCid: row[5] || undefined,
        executionScope: Object.freeze(scopes[index])}))),
  });
}

/** Inspect checked task readiness. A snapshot grants no start or input custody. */
export function inspectTaskProgress(prepared, compilation, admission, definition,
  authority, durableWires) {
  return taskProgressSnapshot(admittedTaskProgress(prepared, compilation,
    admission, definition, authority, durableWires));
}

/** Prepare a checked task claim. The Host must commit it before any send. */
export function prepareTaskPhysicalStart(prepared, compilation, admission, definition,
  authority, durableWires, requested, retained, claim) {
  const keys = ['taskKey', 'dispatchCid', 'definitionCid', 'reserved',
    'unstarted', 'authorized', 'cancelled', 'failed'];
  if (claim === null || typeof claim !== 'object' || Array.isArray(claim) ||
      Object.keys(claim).sort().join('\0') !== keys.sort().join('\0') ||
      [claim.taskKey, claim.dispatchCid, claim.definitionCid].some(value => typeof value !== 'string') ||
      [claim.reserved, claim.unstarted, claim.authorized, claim.cancelled, claim.failed]
        .some(value => typeof value !== 'boolean')) {
    throw new TypeError('InvalidRunHostTaskStart');
  }
  const progress = admittedTaskProgress(prepared, compilation, admission, definition,
    authority, durableWires);
  return checked(owner.clientValuesHostPrepareRemoteTaskPhysicalStart(
    progress, claim.taskKey, claim.dispatchCid, requireHandle(requests, requested),
    requireHandle(requests, retained), claim.definitionCid, claim.reserved,
    claim.unstarted, claim.authorized, claim.cancelled, claim.failed),
  'RunHostTaskStartRejected');
}

/** Project the unpublished whole Run without committing, starting or releasing it. */
export function projectTaskSiteRun(prepared, compilation, admission, definition,
  authority, durableWires, observedAt, cancellationRequested = false,
  claimedTaskKeys = []) {
  if (typeof observedAt !== 'string' || typeof cancellationRequested !== 'boolean' ||
      !Array.isArray(claimedTaskKeys) ||
      claimedTaskKeys.some(key => typeof key !== 'string')) {
    throw new TypeError('InvalidRunHostTaskRunProjection');
  }
  const value = admittedTaskProgress(prepared, compilation, admission,
    definition, authority, durableWires);
  const projected = checked(owner.clientValuesHostProjectRemoteTaskRun(
    value, observedAt, cancellationRequested, claimedTaskKeys),
  'RunHostTaskRunProjectionRejected');
  const fields = owner.clientValuesHostRemoteTaskRunFields(projected);
  const work = owner.clientValuesHostRemoteTaskRunWork(projected);
  const progress = taskProgressSnapshot(value);
  const next = Number(fields[2]);
  return Object.freeze({...progress, stateWire: fields[0], execution: fields[1],
    nextTask: next < 0 ? undefined : next, publicationReady: fields[3] === '1',
    tasks: Object.freeze(progress.tasks.map((task, index) =>
      Object.freeze({...task, nextWork: work[index]}))),
  });
}

/** Project an admitted durable Site record bound to this checked Run. */
export function projectSiteRun(prepared, compilation, admission, definition,
  authority, durableWire, observedAt, cancellationRequested = false,
  physicalStartClaimed = false) {
  const task = taskCompilations.has(compilation);
  const compiled = requireHandle(task ? taskCompilations : compilations, compilation);
  const admitted = requireHandle(admissions, admission);
  if (compiled.prepared !== prepared || admitted.prepared !== prepared) {
    throw new TypeError('ForeignRunHostCompilation');
  }
  if ([authority, durableWire, observedAt].some(value =>
      typeof value !== 'string') || typeof cancellationRequested !== 'boolean' ||
      typeof physicalStartClaimed !== 'boolean') {
    throw new TypeError('InvalidSiteObservation');
  }
  checkRunBinding(prepared, admission, definition);
  const fields = checked(task ? owner.clientValuesHostProjectTaskSiteRun(
    requireHandle(preparations, prepared), compiled.value, admitted.value,
    requireHandle(definitions, definition), authority, durableWire, observedAt,
    cancellationRequested, physicalStartClaimed)
    : owner.clientValuesHostProjectSiteRun(
      requireHandle(definitions, definition), compiled.value,
      authority, durableWire, observedAt, cancellationRequested,
      physicalStartClaimed),
  'RunHostSiteProjectionRejected');
  if (fields === undefined) {
    throw Object.assign(new Error('RunHostSiteProjectionRejected'),
      {code: 'RunHostSiteProjectionRejected'});
  }
  return Object.freeze({stateWire: fields[0], execution: fields[1],
    cleanup: fields[2], revision: Number(fields[3]), nextWork: fields[4]});
}

export function prepareRunPhysicalStart(requested, retained, definition,
  definitionCid, reserved, unstarted, authorized, cancelled, failed = false) {
  if (typeof definitionCid !== 'string' ||
      [reserved, unstarted, authorized, cancelled, failed].some(value =>
        typeof value !== 'boolean')) throw new TypeError('InvalidRunHostStart');
  return checked(owner.clientValuesHostPreparePhysicalStart(
    requireHandle(requests, requested), requireHandle(requests, retained),
    requireHandle(definitions, definition), definitionCid, reserved,
    unstarted, authorized, cancelled, failed), 'RunHostStartRejected');
}

export function prepareRunPreStartFailure(requested, retained, definition,
  definitionCid, reserved, unstarted, admissionDenied, cancelled) {
  if (typeof definitionCid !== 'string' ||
      [reserved, unstarted, admissionDenied, cancelled].some(value =>
        typeof value !== 'boolean')) throw new TypeError('InvalidRunHostStart');
  return checked(owner.clientValuesHostPreparePreStartFailure(
    requireHandle(requests, requested), requireHandle(requests, retained),
    requireHandle(definitions, definition), definitionCid, reserved,
    unstarted, admissionDenied, cancelled), 'RunHostStartRejected');
}

export function prepareRunCancellation(definition, definitionCid,
  authorized, terminal, requested) {
  if (typeof definitionCid !== 'string' ||
      [authorized, terminal, requested].some(value =>
        typeof value !== 'boolean')) throw new TypeError('InvalidRunCancellation');
  return checked(owner.clientValuesHostPrepareCancellation(
    requireHandle(definitions, definition), definitionCid, authorized,
    terminal, requested), 'RunHostCancellationRejected');
}

export function issueRunControlObservation(revision, observation) {
  const {requested, unstarted, stopped} = observation ?? {};
  if (!Number.isSafeInteger(revision) || revision < 0 || revision > 2147483647 ||
      observation === null || typeof observation !== 'object' ||
      Array.isArray(observation) ||
      [requested, unstarted, stopped].some(value => typeof value !== 'boolean')) {
    throw new TypeError('InvalidRunControlObservation');
  }
  return JSON.parse(checked(owner.clientValuesHostRunControlObservation(
    revision, requested, unstarted, stopped), 'RunHostControlRejected'));
}
