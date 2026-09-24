import * as owner from './dist/client_values_host_abi.js';

const environments = new WeakMap();
const preparations = new WeakMap();
const compilations = new WeakMap();
const requests = new WeakMap();
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
  return handle(compilations, value, 'values-compilation');
}

export function privateCompilationWires(compilation) {
  const value = requireHandle(compilations, compilation);
  return Object.freeze({
    executablePlan: owner.clientValuesHostPlanWire(value),
    factManifest: owner.clientValuesHostFactManifestWire(value),
    boundTemplate: owner.clientValuesHostTemplateWire(value),
    compiledPlan: owner.clientValuesHostCompiledPlanWire(value),
  });
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
