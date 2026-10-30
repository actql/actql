import {checked} from '../../../host-common/runtime-result.mjs';
import {sendRawKintoneWrite} from './kintone-record-write.mjs';

const fail = code => {throw Object.assign(new Error(code), {code});};
const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const requiredPorts = ['clientProgramKintoneCreateMappingMatchesDeclaration',
  'clientProgramKintoneCreateMappingMatchesRequest', 'clientProgramKintoneCreateExecutionRequest',
  'clientProgramKintoneWriteLimits', 'clientProgramKintoneMutationLimits'];

function originalMapping(moon, mapping, declaration) {
  if (requiredPorts.some(name => typeof moon?.[name] !== 'function')) {
    fail('KintoneCreateExecutionRuntimeUnavailable');
  }
  if (!mapping || !declaration ||
      !moon.clientProgramKintoneCreateMappingMatchesDeclaration(mapping, declaration)) {
    fail('ForeignKintoneCreateMapping');
  }
}

// Mapped values use the same original Form and Mapping. This prepares DATA,
// without provider records, defaults, IDs, insertion decisions or permissions.
export function prepareMappedKintoneCreate({moon, mapping, declaration, bytes, limits}) {
  originalMapping(moon, mapping, declaration);
  if (!(bytes instanceof Uint8Array) || !['maxRequestBytes', 'maxNodes', 'maxDepth',
    'maxFields', 'maxNameUnits', 'maxRows', 'maxIdentityBytes', 'maxComparisonWork']
    .every(name => positive(limits?.[name])) || bytes.byteLength > limits.maxRequestBytes) {
    fail('InvalidKintoneCreateValues');
  }
  const write = moon.clientProgramKintoneWriteLimits(limits.maxFields, limits.maxNameUnits,
    limits.maxNodes, limits.maxDepth, limits.maxRequestBytes, limits.maxRequestBytes);
  const request = moon.clientProgramKintoneMutationLimits(limits.maxRows,
    limits.maxIdentityBytes, limits.maxComparisonWork, limits.maxRequestBytes,
    limits.maxNodes, limits.maxDepth);
  return checked(moon.clientProgramKintoneCreateExecutionRequest(mapping, bytes,
    limits.maxRequestBytes, write, request));
}

// This is a thin caller of the existing physical port, after the Effect Owner's
// original claim. It adds no retries, observations, settlement or cleanup Owner.
export async function sendMappedKintoneCreate({moon, mapping, declaration, request, ...options}) {
  originalMapping(moon, mapping, declaration);
  if (!moon.clientProgramKintoneCreateMappingMatchesRequest(mapping, request)) {
    fail('ForeignKintoneCreateRequest');
  }
  return sendRawKintoneWrite({...options, moon, kind: 'create', request});
}

// Pure request/response DATA for one independently authorized Form read. The
// standard Host supplies its fixed POST+GET-override endpoint and owns the
// physical child. No Credential, grant, read, write or cleanup is created here.
export function prepareMappedKintoneCreateFormCheck({moon, mapping, declaration, request, limits}) {
  originalMapping(moon, mapping, declaration);
  const app = moon.clientProgramKintoneCreateApp, count = moon.clientProgramKintoneCreateCount,
    matches = moon.clientProgramKintoneCreateMappingMatchesRequest,
    formLimits = moon.clientProgramKintoneFormLimits, recheck = moon.clientProgramKintoneCreateRecheckForm;
  if (![app,count,matches,formLimits,recheck].every(value => typeof value === 'function') ||
      !['maxRequestBytes','maxResponseBytes','maxNodes','maxDepth','maxFields','maxNameUnits']
        .every(name => positive(limits?.[name]))) fail('InvalidKintoneCreateFormCheck');
  if (Reflect.apply(count,moon,[request]) !== 1 || !Reflect.apply(matches,moon,[mapping,request])) {
    fail('ForeignKintoneCreateRequest');
  }
  const appId = Reflect.apply(app,moon,[request]);
  if (typeof appId !== 'string' || !/^[1-9][0-9]*$/u.test(appId) || appId.length > limits.maxRequestBytes - 10) {
    fail('KintoneWriteRequestLimit');
  }
  const maxResponseBytes = limits.maxResponseBytes;
  const bounded = Reflect.apply(formLimits,moon,[maxResponseBytes,limits.maxNodes,
    limits.maxDepth,limits.maxFields,limits.maxNameUnits]);
  const body = JSON.stringify({app:appId});
  return Object.freeze({body,
    project(observation) {
      if (!(observation?.body instanceof Uint8Array) || observation.body.byteLength > maxResponseBytes ||
          !Number.isInteger(observation.statusCode)) fail('InvalidKintoneCreateFormObservation');
      if (observation.statusCode !== 200) fail('KintoneWriteReadRejected');
      return checked(Reflect.apply(recheck,moon,[request,observation.body,bounded]));
    }});
}


// One actual typed CREATE acknowledgement, not bytes-as-success. The original
// Effect Owner still owns saved response/dispatch correlation, current grant,
// footprint and terminal Ledger admission. No response is retried here.
export function projectMappedKintoneCreateOutcome({moon, mapping, declaration,
  request, response, preview, memberIndex, rowIndex, limits}) {
  originalMapping(moon, mapping, declaration);
  const names = ['clientProgramKintoneCreatePreviewOutcome',
    'clientProgramKintoneCreatePreviewOutcomeWire', 'clientProgramKintoneCreatePreviewOutcomeRowCid',
    'clientProgramKintoneCreatePreviewOutcomeResponseSha256', 'clientProgramKintoneCreatePreviewOutcomeMatches'];
  if (names.some(name => typeof moon?.[name] !== 'function')) {
    fail('KintoneCreateOutcomeRuntimeUnavailable');
  }
  if (!Number.isSafeInteger(memberIndex) || memberIndex < 0 ||
      !Number.isSafeInteger(rowIndex) || rowIndex < 0 ||
      !['maxRequestBytes', 'maxResponseBytes', 'maxNodes', 'maxDepth', 'maxFields',
        'maxNameUnits', 'maxRows', 'maxIdentityBytes', 'maxComparisonWork']
        .every(name => positive(limits?.[name]))) fail('InvalidKintoneCreateOutcome');
  const write = moon.clientProgramKintoneWriteLimits(limits.maxFields, limits.maxNameUnits,
    limits.maxNodes, limits.maxDepth, limits.maxRequestBytes, limits.maxRequestBytes);
  const bounds = moon.clientProgramKintoneMutationLimits(limits.maxRows,
    limits.maxIdentityBytes, limits.maxComparisonWork, limits.maxResponseBytes,
    limits.maxNodes, limits.maxDepth);
  const projected = checked(moon.clientProgramKintoneCreatePreviewOutcome(mapping,
    request, response, preview, memberIndex, rowIndex, limits.maxRequestBytes, write, bounds));
  if (!moon.clientProgramKintoneCreatePreviewOutcomeMatches(projected,
    mapping, request, preview, memberIndex, rowIndex)) fail('ForeignKintoneCreateOutcome');
  return Object.freeze({kind: 'typed-success-response', projected,
    outcome: JSON.parse(moon.clientProgramKintoneCreatePreviewOutcomeWire(projected)),
    rowPreviewCid: moon.clientProgramKintoneCreatePreviewOutcomeRowCid(projected),
    responseSha256: moon.clientProgramKintoneCreatePreviewOutcomeResponseSha256(projected)});
}

// Provider DATA for the standard Row Effect classifier. The enclosing common
// owner already compares request facts with its exact mapped/approved row and
// binds this outcome to the original saved response and durable claim. This
// projection supplies no Preview, authority, physical call or terminal receipt.
export function projectMappedKintoneCreateResponseOutcome({moon, mapping, declaration,
  request, observation, limits}) {
  originalMapping(moon, mapping, declaration);
  const names = ['clientProgramKintoneCreateMappingMatchesRequest',
    'clientProgramKintoneCreateResponse', 'clientProgramKintoneCreateEffectOutcome',
    'clientProgramKintoneCreateEffectOutcomeWire',
    'clientProgramKintoneCreateEffectOutcomeResponseSha256',
    'clientProgramKintoneCreateEffectOutcomeMatchesRequest'];
  if (names.some(name => typeof moon?.[name] !== 'function')) {
    fail('KintoneCreateOutcomeRuntimeUnavailable');
  }
  if (!moon.clientProgramKintoneCreateMappingMatchesRequest(mapping, request)) {
    fail('ForeignKintoneCreateRequest');
  }
  if (!(observation?.body instanceof Uint8Array) || !Number.isInteger(observation.statusCode) ||
      !['maxResponseBytes', 'maxNodes', 'maxDepth', 'maxRows', 'maxIdentityBytes',
        'maxComparisonWork'].every(name => positive(limits?.[name])) ||
      observation.body.byteLength > limits.maxResponseBytes) fail('InvalidKintoneCreateOutcome');
  const bounds = moon.clientProgramKintoneMutationLimits(limits.maxRows,
    limits.maxIdentityBytes, limits.maxComparisonWork, limits.maxResponseBytes,
    limits.maxNodes, limits.maxDepth);
  const response = checked(moon.clientProgramKintoneCreateResponse(request,
    observation.statusCode, observation.body, bounds));
  const projected = checked(moon.clientProgramKintoneCreateEffectOutcome(request, response, bounds));
  if (!moon.clientProgramKintoneCreateEffectOutcomeMatchesRequest(projected, request)) {
    fail('ForeignKintoneCreateOutcome');
  }
  return Object.freeze({kind: 'typed-success-response', projected,
    outcome: JSON.parse(moon.clientProgramKintoneCreateEffectOutcomeWire(projected)),
    responseSha256: moon.clientProgramKintoneCreateEffectOutcomeResponseSha256(projected)});
}
